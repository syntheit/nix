#!/usr/bin/env bash
# Argus — container update manager
# Replaces Watchtower with systemd-native image updates, pre-update backups, and rollback support.

CONFIG="/etc/argus/config.json"
STATE_DIR="/var/lib/argus/state"
BACKUP_DIR="/var/lib/argus/backups"
LOCK_FILE="/var/lib/argus/lock"
LOG_TAG="argus"

# --- Logging ---

log() {
  local msg="$*"
  logger -t "$LOG_TAG" "$msg"
  echo "$msg" >&2
}

log_error() {
  local msg="$*"
  logger -t "$LOG_TAG" -p user.err "$msg"
  echo "ERROR: $msg" >&2
}

die() {
  log_error "$@"
  exit 1
}

# --- Locking ---

acquire_lock() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    die "Another argus instance is running"
  fi
}

# --- Config helpers ---

jq_config() {
  jq -r "$1" "$CONFIG"
}

get_containers() {
  jq_config '.containers | keys[]'
}

get_image() {
  jq_config ".containers[\"$1\"].image"
}

get_policy() {
  jq_config ".containers[\"$1\"].policy"
}

get_container_backups() {
  jq_config ".containers[\"$1\"].backups[]" 2>/dev/null || true
}

get_retention() {
  jq_config '.retention'
}

# --- State helpers ---

get_state() {
  local name="$1"
  local file="$STATE_DIR/${name}.json"
  if [ -f "$file" ]; then
    cat "$file"
  else
    echo '{}'
  fi
}

# set_state <name> [jq args...] <jq filter>
# All arguments after name are passed directly to jq.
set_state() {
  local name="$1"
  shift
  local file="$STATE_DIR/${name}.json"
  local current
  current=$(get_state "$name")
  echo "$current" | jq "$@" > "${file}.tmp"
  mv "${file}.tmp" "$file"
}

state_field() {
  local name="$1"
  local field="$2"
  get_state "$name" | jq -r ".$field // empty"
}

# --- Backup ---

do_backup() {
  local backup_name="$1"
  local btype bcontainer bdatabase buser
  btype=$(jq_config ".backups[\"$backup_name\"].type")
  bcontainer=$(jq_config ".backups[\"$backup_name\"].container")
  bdatabase=$(jq_config ".backups[\"$backup_name\"].database")
  buser=$(jq_config ".backups[\"$backup_name\"].user")

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="$BACKUP_DIR/${backup_name}_${timestamp}.sql"

  log "Backing up $backup_name ($btype via $bcontainer)..."

  local rc=0
  if [ "$btype" = "postgres" ]; then
    docker exec "$bcontainer" pg_dump -U "$buser" "$bdatabase" > "$backup_file" 2> >(logger -t "$LOG_TAG" -p user.err) || rc=$?
  elif [ "$btype" = "mariadb" ]; then
    docker exec "$bcontainer" sh -c 'mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" --all-databases' > "$backup_file" 2> >(logger -t "$LOG_TAG" -p user.err) || rc=$?
  else
    log_error "Unknown backup type: $btype"
    return 1
  fi

  if [ "$rc" -ne 0 ] || [ ! -s "$backup_file" ]; then
    rm -f "$backup_file"
    log_error "Backup $backup_name failed"
    return 1
  fi

  log "Backup saved: $backup_file ($(du -h "$backup_file" | cut -f1))"

  # Rotate: keep only N newest
  local retention
  retention=$(get_retention)
  local old_backups
  old_backups=$(find "$BACKUP_DIR" -name "${backup_name}_*.sql" -type f | sort -r | tail -n +"$((retention + 1))" || true)
  if [ -n "$old_backups" ]; then
    echo "$old_backups" | xargs rm -f --
  fi

  return 0
}

# --- Core: check ---

_check_all() {
  local containers updated=0 skipped=0 checked=0
  mapfile -t containers < <(get_containers)
  local total=${#containers[@]}

  log "Checking $total containers for updates..."

  # Deduplicate images to avoid pulling the same image multiple times
  declare -A image_pulled
  for name in "${containers[@]}"; do
    local image
    image=$(get_image "$name")
    if [ "${image_pulled[$image]:-}" != "1" ]; then
      if docker pull "$image" > /dev/null 2>&1; then
        image_pulled[$image]=1
      else
        log_error "Failed to pull $image"
        image_pulled[$image]="failed"
      fi
    fi
  done

  for name in "${containers[@]}"; do
    local image
    image=$(get_image "$name")
    checked=$((checked + 1))

    if [ "${image_pulled[$image]:-}" = "failed" ]; then
      skipped=$((skipped + 1))
      continue
    fi

    # Get the ID of the pulled image
    local pulled_id
    pulled_id=$(docker image inspect "$image" --format='{{.Id}}' 2>/dev/null || true)

    if [ -z "$pulled_id" ]; then
      skipped=$((skipped + 1))
      continue
    fi

    # Get the running container's image ID
    local running_id=""
    if docker inspect "$name" > /dev/null 2>&1; then
      running_id=$(docker inspect "$name" --format='{{.Image}}' 2>/dev/null || true)
    fi

    local current_digest
    current_digest=$(state_field "$name" "current_digest")
    local now
    now=$(date -Is)

    if [ -z "$current_digest" ]; then
      # First time seeing this container — initialize state, no update triggered
      set_state "$name" \
        --arg cd "$pulled_id" \
        --arg lc "$now" \
        '. + {current_digest: $cd, update_available: false, last_checked: $lc}'
    elif [ -n "$running_id" ] && [ "$running_id" != "$pulled_id" ]; then
      set_state "$name" \
        --arg ad "$pulled_id" \
        --arg lc "$now" \
        '. + {update_available: true, available_digest: $ad, last_checked: $lc}'
      updated=$((updated + 1))
      log "Update available: $name"
    else
      set_state "$name" \
        --arg lc "$now" \
        '. + {update_available: false, last_checked: $lc}'
    fi
  done

  log "Check complete: $checked checked, $updated updates available, $skipped skipped"
}

# --- Core: update ---

_do_update() {
  local name="$1"
  local image service
  image=$(get_image "$name")
  service="docker-${name}.service"

  # Get current container's image ID for rollback tagging
  local current_id=""
  if docker inspect "$name" > /dev/null 2>&1; then
    current_id=$(docker inspect "$name" --format='{{.Image}}' 2>/dev/null || true)
  fi

  local current_digest
  current_digest=$(state_field "$name" "current_digest")

  # Tag current image for rollback
  if [ -n "$current_id" ]; then
    if ! docker tag "$current_id" "argus/rollback/${name}:latest" 2>/dev/null; then
      log "Warning: failed to create rollback tag for $name"
    fi
  fi

  # Restart via systemd (picks up the already-pulled new image)
  log "Restarting $name..."
  if ! systemctl restart "$service" 2>/dev/null; then
    log_error "Failed to restart $service"
    return 1
  fi

  # Wait for container to be running (up to 60s)
  local _i
  for _i in $(seq 1 30); do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
      break
    fi
    sleep 2
  done

  if ! systemctl is-active --quiet "$service" 2>/dev/null; then
    log_error "Container $name failed to start after update"
    return 1
  fi

  # Update state
  local new_id now
  new_id=$(docker image inspect "$image" --format='{{.Id}}' 2>/dev/null || true)
  now=$(date -Is)

  set_state "$name" \
    --arg cd "$new_id" \
    --arg pd "$current_digest" \
    --arg lu "$now" \
    '. + {current_digest: $cd, previous_digest: $pd, update_available: false, last_updated: $lu}'

  log "Updated $name successfully"
  return 0
}

_update_containers() {
  local target="${1:-}"
  local containers_to_update=()

  if [ -n "$target" ]; then
    # Verify container exists in config
    if [ "$(jq_config ".containers[\"$target\"] // empty")" = "" ]; then
      die "Container '$target' is not managed by argus"
    fi
    containers_to_update=("$target")
  else
    # All auto containers with available updates
    mapfile -t all_containers < <(get_containers)
    local name
    for name in "${all_containers[@]}"; do
      local policy
      policy=$(get_policy "$name")
      local update_available
      update_available=$(get_state "$name" | jq -r '.update_available // false')
      if [ "$policy" = "auto" ] && [ "$update_available" = "true" ]; then
        containers_to_update+=("$name")
      fi
    done
  fi

  if [ ${#containers_to_update[@]} -eq 0 ]; then
    log "No containers to update"
    return 0
  fi

  log "Updating ${#containers_to_update[@]} container(s): ${containers_to_update[*]}"

  # Collect unique backups needed
  declare -A needed_backups
  local name
  for name in "${containers_to_update[@]}"; do
    mapfile -t container_backups < <(get_container_backups "$name")
    local backup
    for backup in "${container_backups[@]}"; do
      if [ -n "$backup" ]; then
        needed_backups[$backup]=1
      fi
    done
  done

  # Run backups
  declare -A backup_failed
  local backup_name
  for backup_name in "${!needed_backups[@]}"; do
    if ! do_backup "$backup_name"; then
      backup_failed[$backup_name]=1
    fi
  done

  # Update containers
  local updated=0 failed=0
  for name in "${containers_to_update[@]}"; do
    # Check if any required backup failed
    local skip=false
    mapfile -t container_backups < <(get_container_backups "$name")
    local backup
    for backup in "${container_backups[@]}"; do
      if [ -n "$backup" ] && [ "${backup_failed[$backup]:-}" = "1" ]; then
        log_error "Skipping $name: required backup '$backup' failed"
        skip=true
        break
      fi
    done
    if [ "$skip" = true ]; then
      failed=$((failed + 1))
      continue
    fi

    if _do_update "$name"; then
      updated=$((updated + 1))
    else
      failed=$((failed + 1))
    fi
  done

  log "Update complete: $updated succeeded, $failed failed"
}

# --- Commands ---

cmd_status() {
  if [ ! -f "$CONFIG" ]; then
    die "Config not found at $CONFIG — is argus enabled in your NixOS config?"
  fi

  # Header
  printf "\n  %-28s %-10s %-8s %-20s %s\n" "Container" "Status" "Policy" "Last Updated" "Update"
  printf "  %-28s %-10s %-8s %-20s %s\n" "─────────" "──────" "──────" "────────────" "──────"

  mapfile -t containers < <(get_containers)
  local name
  for name in "${containers[@]}"; do
    local policy
    policy=$(get_policy "$name")

    # Container status
    local status
    if systemctl is-active --quiet "docker-${name}.service" 2>/dev/null; then
      status="running"
    else
      status="stopped"
    fi

    # Last updated
    local last_updated
    last_updated=$(state_field "$name" "last_updated")
    if [ -n "$last_updated" ]; then
      last_updated=$(date -d "$last_updated" "+%b %d, %H:%M" 2>/dev/null || echo "$last_updated")
    else
      last_updated="-"
    fi

    # Update info
    local update_info
    local update_available
    update_available=$(get_state "$name" | jq -r '.update_available // "unknown"')
    local last_checked
    last_checked=$(state_field "$name" "last_checked")

    if [ -z "$last_checked" ]; then
      update_info="not checked"
    elif [ "$update_available" = "true" ]; then
      update_info="update available"
    elif [ "$status" = "stopped" ]; then
      update_info="down"
    else
      update_info="up to date"
    fi

    printf "  %-28s %-10s %-8s %-20s %s\n" "$name" "$status" "$policy" "$last_updated" "$update_info"
  done

  # Backup summary
  local backup_count
  backup_count=$(find "$BACKUP_DIR" -name "*.sql" -type f 2>/dev/null | wc -l)
  printf "\n  Backups: %d stored in %s\n\n" "$backup_count" "$BACKUP_DIR"
}

cmd_check() {
  acquire_lock
  _check_all
}

cmd_update() {
  acquire_lock

  local target="${1:-}"

  # If updating a specific container, pull its image first
  if [ -n "$target" ]; then
    local image
    image=$(get_image "$target")
    if [ -z "$image" ] || [ "$image" = "null" ]; then
      die "Container '$target' is not managed by argus"
    fi
    log "Pulling $image..."
    if ! docker pull "$image" > /dev/null 2>&1; then
      die "Failed to pull $image"
    fi
    # Check if actually newer
    local pulled_id running_id
    pulled_id=$(docker image inspect "$image" --format='{{.Id}}' 2>/dev/null || true)
    running_id=""
    if docker inspect "$target" > /dev/null 2>&1; then
      running_id=$(docker inspect "$target" --format='{{.Image}}' 2>/dev/null || true)
    fi
    if [ "$pulled_id" = "$running_id" ]; then
      log "$target is already up to date"
      return 0
    fi
    set_state "$target" \
      --arg ad "$pulled_id" \
      '. + {update_available: true, available_digest: $ad}'
  fi

  _update_containers "$target"
}

cmd_auto() {
  acquire_lock
  log "Starting automatic update run"
  _check_all
  _update_containers ""
  log "Automatic update run complete"
}

cmd_rollback() {
  local name="${1:?Usage: argus rollback <container>}"
  acquire_lock

  if [ "$(jq_config ".containers[\"$name\"] // empty")" = "" ]; then
    die "Container '$name' is not managed by argus"
  fi

  local image
  image=$(get_image "$name")
  local rollback_tag="argus/rollback/${name}:latest"

  # Save current digest before rollback (so we can swap previous_digest)
  local pre_rollback_digest
  pre_rollback_digest=$(state_field "$name" "current_digest")

  # Try local rollback tag
  if docker image inspect "$rollback_tag" > /dev/null 2>&1; then
    log "Rolling back $name using local rollback image..."
    docker tag "$rollback_tag" "$image"
    if ! systemctl restart "docker-${name}.service" 2>/dev/null; then
      die "Failed to restart $name after rollback"
    fi
  else
    die "No rollback image available for $name (rollback tag not found locally)"
  fi

  # Wait for container
  local _i
  for _i in $(seq 1 15); do
    if systemctl is-active --quiet "docker-${name}.service" 2>/dev/null; then
      break
    fi
    sleep 2
  done

  if ! systemctl is-active --quiet "docker-${name}.service" 2>/dev/null; then
    die "Container $name failed to start after rollback"
  fi

  # Update state: swap current and previous digests
  local previous_digest now
  previous_digest=$(state_field "$name" "previous_digest")
  now=$(date -Is)
  set_state "$name" \
    --arg cd "$previous_digest" \
    --arg pd "$pre_rollback_digest" \
    --arg lu "$now" \
    '. + {current_digest: $cd, previous_digest: $pd, update_available: false, last_updated: $lu}'

  log "Rolled back $name successfully"

  # Point user to backups
  if [ -d "$BACKUP_DIR" ] && [ "$(find "$BACKUP_DIR" -name '*.sql' -type f 2>/dev/null | head -1)" ]; then
    echo "Database backups available in $BACKUP_DIR" >&2
  fi
}

cmd_logs() {
  journalctl -t "$LOG_TAG" "$@"
}

print_usage() {
  cat <<'EOF'
Argus — container update manager

Usage:
  argus status                Show status of all managed containers
  argus check                 Pull images and check for available updates
  argus update [container]    Update a specific container, or all auto containers
  argus rollback <container>  Rollback a container to its previous image
  argus logs [...]            Show argus log entries (args passed to journalctl)

EOF
}

# --- Main ---

case "${1:-}" in
  status)   cmd_status ;;
  check)    cmd_check ;;
  update)   shift; cmd_update "${1:-}" ;;
  auto)     cmd_auto ;;
  rollback) shift; cmd_rollback "${1:-}" ;;
  logs)     shift; cmd_logs "$@" ;;
  -h|--help|help) print_usage ;;
  *)        print_usage; exit 1 ;;
esac
