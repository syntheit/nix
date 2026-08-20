{ pkgs, ... }:

# Native aarch64-linux builder VM (QEMU + hvf), replicating what nix-darwin's
# nix.linux-builder module does — that module asserts `nix.enable`, which is
# off here because Determinate nix owns /etc/nix/nix.conf. The three pieces it
# would have wired up, wired by hand:
#
#   1. launchd daemon runs darwin.linux-builder's create-builder: generates
#      /etc/nix/builder_ed25519{,.pub} on first boot, then keeps a NixOS VM
#      (1 core / 3 GiB / 20 GiB qcow2 in /var/lib/linux-builder) listening on
#      ssh localhost:31022.
#   2. /etc/nix/machines registers the builder with the daemon. Nix's default
#      is `builders = @/etc/nix/machines` and Determinate's nix.conf doesn't
#      override `builders`, so no nix.conf change is needed.
#   3. /etc/ssh/ssh_config.d alias so ssh resolves the `linux-builder` host
#      (macOS's stock ssh_config includes ssh_config.d/*).
#
# `builders-use-substitutes = true` lives in /etc/nix/nix.custom.conf, the
# Determinate-designated file for manual settings (connect-timeout etc. are
# already there).
#
# The stock VM is 1 core / 3 GiB / 20 GiB; this mini idles most of the time,
# so give the builder most of the machine (10 cores / 16 GiB host). QEMU only
# faults guest RAM in as it's used and the qcow2 is sparse, so the idle cost
# is a mostly-sleeping QEMU process. NOTE: diskSize only applies when
# run-nixos-vm creates the image — to grow an existing builder, stop the
# daemon, delete /var/lib/linux-builder/nixos.qcow2, start it again (wipes
# the VM's build cache, nothing else).

let
  linux-builder = pkgs.darwin.linux-builder.override (old: {
    modules = (old.modules or [ ]) ++ [
      (
        { lib, ... }:
        {
          # the nix-builder-vm profile pins all three at normal priority
          virtualisation.cores = lib.mkForce 8;
          virtualisation.memorySize = lib.mkForce 8192;
          virtualisation.diskSize = lib.mkForce (60 * 1024);

          # Auto-GC INSIDE the guest. This builder takes ALL of harbor's
          # offloaded aarch64 phone-app builds, piling up dead store paths at
          # ~20 GB/day. A weekly GC timer was WAY too slow: the 59 GiB guest
          # filled to read-only in ~2 days, long before GC ever fired — that
          # was the real "fills every couple days" root cause (diagnosed
          # 2026-08-20). The PRIMARY safety net is now continuous, reactive GC
          # via min-free/max-free below: the nix daemon evicts dead paths
          # mid-build whenever free space drops under min-free (15 GiB),
          # capping guest usage around 30-40 GiB with zero timer involvement.
          # The daily GC + 3-day retention below is a belt-and-suspenders
          # backstop only. Note the guest can't see the *host* APFS running
          # out, so it can't rely on that alone.
          nix.gc = {
            automatic = true;
            dates = "daily";
            options = "--delete-older-than 3d";
          };
          # The nix-builder-vm profile already pins min-free/max-free at normal
          # priority, so these need mkForce (same as the sizing options above).
          nix.settings = {
            min-free = lib.mkForce (15 * 1024 * 1024 * 1024); # 15 GiB
            max-free = lib.mkForce (30 * 1024 * 1024 * 1024); # 30 GiB
          };
        }
      )
    ];
  });
in
{
  system.activationScripts.preActivation.text = ''
    mkdir -p /var/lib/linux-builder
  '';

  launchd.daemons.linux-builder = {
    # The VM shares host CA certs via TMPDIR; macOS purges /tmp files idle for
    # 3+ days (sleeping laptop → vanished certs), so use /run instead.
    environment.NIX_SSL_CERT_FILE = "/etc/nix/macos-keychain.crt";
    script = ''
      export TMPDIR=/run/org.nixos.linux-builder USE_TMPDIR=1
      rm -rf $TMPDIR
      mkdir -p $TMPDIR
      trap "rm -rf $TMPDIR" EXIT
      # Pin the builder identity. add-keys (inside create-builder) generates a
      # FRESH keypair whenever ./keys is empty — and the keys dir gets wiped by
      # disk-full recoveries and even darwin-rebuild switch (both observed
      # 2026-07-18). Every regeneration silently desyncs harbor's sops-pinned
      # copy of this key → "Permission denied" on all remote builds.
      # /etc/nix/builder_ed25519 is the canonical copy; reseed ./keys from it
      # (cwd is /var/lib/linux-builder) so add-keys never regenerates. A new
      # key can now only appear if BOTH copies are lost — if you ever rotate
      # it on purpose, update harbor's sops secret mac_builder_ssh_key too.
      if [ -f /etc/nix/builder_ed25519 ] && [ -f /etc/nix/builder_ed25519.pub ]; then
        mkdir -p keys
        cp -f /etc/nix/builder_ed25519 keys/builder_ed25519
        cp -f /etc/nix/builder_ed25519.pub keys/builder_ed25519.pub
        chmod 600 keys/builder_ed25519
        chmod 644 keys/builder_ed25519.pub
      fi
      ${linux-builder}/bin/create-builder
    '';
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      WorkingDirectory = "/var/lib/linux-builder";
    };
  };

  # QEMU under hvf occasionally hard-hangs under heavy build load (3x on
  # 2026-07-18: process stays alive, port 31022 LISTENs but accept() is never
  # serviced, so every connection stalls at banner exchange / gets refused
  # once the backlog fills). KeepAlive can't catch this — the process never
  # exits — so probe the guest's sshd every 2 minutes and force-restart the
  # builder after 3 consecutive failures (~6 min of grace, enough to never
  # fire during a normal boot or store.img regeneration).
  launchd.daemons.linux-builder-watchdog = {
    script = ''
      state=/var/lib/linux-builder/watchdog-failures
      # Health check is sshd-reachability only: a plain `ssh ... true`. Do NOT
      # try to probe /nix writability here — the ssh `builder` user is non-root
      # and /nix in the guest is root:root 0755, so a `test -w /nix` / touch
      # probe as that user always false-fails, wedging the watchdog into a
      # force-restart loop every ~6 min (observed in production). The disk-full
      # / read-only-store scenario is instead guarded by (a) the separate
      # linux-builder-disk-watchdog below (host `df` + ghost-file detection) and
      # (b) the qcow2 size cap + guest GC that keep the host from filling in the
      # first place.
      if /usr/bin/ssh -o ConnectTimeout=10 -o BatchMode=yes \
           -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -i /etc/nix/builder_ed25519 -p 31022 builder@localhost \
           true \
           2>/dev/null; then
        rm -f "$state"
        exit 0
      fi
      n=$(( $(cat "$state" 2>/dev/null || echo 0) + 1 ))
      echo "$n" > "$state"
      if [ "$n" -ge 3 ]; then
        rm -f "$state"
        echo "$(/bin/date '+%Y-%m-%dT%H:%M:%S') watchdog: 3 consecutive failures (sshd unreachable), force-restarting builder" >> /var/lib/linux-builder/watchdog.log
        /usr/bin/pkill -9 -f qemu-system-aarch64 || true
        /bin/launchctl kickstart -k system/org.nixos.linux-builder
      fi
    '';
    serviceConfig.StartInterval = 120;
  };

  # A SECOND, slower (5 min) watchdog guarding against the host-side disk leak
  # that the sshd/writability probe above can't see coming. On 2026-08 the
  # builder's disk image /var/lib/linux-builder/nixos.qcow2 was deleted from
  # disk while the QEMU process still had it open. On Unix a deleted-but-open
  # file's blocks aren't freed until the last fd closes, so QEMU kept the
  # ~91 GiB "ghost" image alive — invisible to du/find/Finder — and went on
  # writing toward its 100 GiB ceiling, driving the mini's APFS container to
  # 0 bytes free. That froze macOS AND wedged the builder (guest /nix went
  # read-only). This daemon detects the two signatures directly on the host:
  # (1) a deleted-but-open qcow2 held by QEMU (the ghost-file leak), and
  # (2) low free space on /. Only the leak signature auto-restarts (that's the
  # one a restart actually cures, by closing the fd and freeing the blocks);
  # low disk alone only logs, since a restart wouldn't necessarily help and
  # could mask a real capacity problem.
  #
  # NOTE: there is no host-side notification mechanism on the mini (checked:
  # only a `telegram` homebrew cask + harbor's Elliot bot exist, and neither
  # is reachable from this launchd daemon context), so critical conditions are
  # surfaced via a LOUD log line only. A future maintainer could wire an
  # ntfy POST or an `osascript display notification` here.
  launchd.daemons.linux-builder-disk-watchdog = {
    script = ''
      # Editable thresholds (free space on /, in KiB).
      warn_kib=15728640   # 15 GiB
      crit_kib=5242880    # 5 GiB

      # (a) Ghost-file detection: does any process hold a DELETED nixos.qcow2
      # open? `lsof +L1` lists only files whose on-disk link count is < 1,
      # i.e. unlinked-but-still-open — exactly the leaking ghost image.
      leak=0
      if /usr/sbin/lsof +L1 2>/dev/null | grep -qi nixos.qcow2; then leak=1; fi

      # (b) Host disk-pressure floor: free KiB on / is the 4th field of df's
      # data line (NR==2).
      free=$(/bin/df -k / | awk 'NR==2 {print $4}')

      # (c) Decision logic (conservative — never restart merely for low disk).
      if [ "$leak" -eq 1 ]; then
        # Leak signature present: a deleted nixos.qcow2 is still open and its
        # blocks are leaking. Force-restart to close the fd and free the space,
        # regardless of the current disk level.
        echo "$(/bin/date '+%Y-%m-%dT%H:%M:%S') disk-watchdog: DELETED-BUT-OPEN nixos.qcow2 detected (ghost-file leak) — space is leaking, force-restarting builder" >> /var/lib/linux-builder/watchdog.log
        /usr/bin/pkill -9 -f qemu-system-aarch64 || true
        /bin/launchctl kickstart -k system/org.nixos.linux-builder
      elif [ "$free" -lt "$crit_kib" ]; then
        # Critically low disk but NO leak signature — do NOT restart; a restart
        # wouldn't reclaim anything here and could hide a real capacity issue.
        echo "$(/bin/date '+%Y-%m-%dT%H:%M:%S') disk-watchdog: CRITICAL free space on / is $free KiB (< $crit_kib KiB) and no ghost-file leak — NOT restarting, manual attention needed" >> /var/lib/linux-builder/watchdog.log
      elif [ "$free" -lt "$warn_kib" ]; then
        # Warning band — log only, no action.
        echo "$(/bin/date '+%Y-%m-%dT%H:%M:%S') disk-watchdog: WARNING free space on / is $free KiB (< $warn_kib KiB)" >> /var/lib/linux-builder/watchdog.log
      fi
      # Healthy: exit 0 silently so the log isn't spammed every 5 minutes.
    '';
    serviceConfig.StartInterval = 300;
  };

  environment.etc."ssh/ssh_config.d/100-linux-builder.conf".text = ''
    Host linux-builder
      User builder
      Hostname localhost
      HostKeyAlias linux-builder
      Port 31022
      IdentityFile /etc/nix/builder_ed25519
  '';

  # Fields: URI systems sshKey maxJobs speedFactor supported mandatory pubHostKey.
  # maxJobs matches the VM's cores. The host key is baked into the stock
  # VM image; this is the same base64 blob nix-darwin's module hardcodes.
  environment.etc."nix/machines".text = ''
    ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 8 1 kvm,benchmark,big-parallel - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=
  '';
}
