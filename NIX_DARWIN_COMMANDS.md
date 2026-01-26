# Nix-Darwin Command Reference

## TL;DR

```bash
# Apply configuration changes
darwin-rebuild switch --flake .#aegean

# Update flake inputs
nix flake update

# Test configuration without activating
darwin-rebuild build --flake .#aegean

# Rollback to previous generation
darwin-rebuild --rollback

# Garbage collection
nix-collect-garbage -d
```

---

## Initial Setup

### First-Time Installation

```bash
# Install Nix (if not already installed)
sh <(curl -L https://nixos.org/nix/install)

# Install nix-darwin
nix run nix-darwin -- switch --flake ~/.config/nix-darwin

# For this repo
cd /Users/daniel/Dev/nixos
git add .
git commit -m "Initial commit" # Flakes need changes committed or staged
sudo nix run nix-darwin -- switch --flake .#aegean
```

---

## Daily Usage Commands

### Rebuild System Configuration

```bash
# Build and activate (most common)
darwin-rebuild switch --flake .#aegean

# Build only (test without activating)
darwin-rebuild build --flake .#aegean

# Build and view changelog
darwin-rebuild switch --flake .#aegean --show-trace

# Dry run (show what would change)
darwin-rebuild build --flake .#aegean --dry-run
```

### Update Dependencies

```bash
# Update all flake inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Update and rebuild in one command
nix flake update && darwin-rebuild switch --flake .#aegean
```

### Check Configuration

```bash
# Validate flake syntax
nix flake check

# Show flake info
nix flake show

# Show flake metadata
nix flake metadata
```

---

## System Management

### Generations

```bash
# List all generations
darwin-rebuild --list-generations

# Rollback to previous generation
darwin-rebuild --rollback

# Switch to specific generation
darwin-rebuild switch --switch-generation 42

# Delete old generations (keep last 7 days)
nix-collect-garbage --delete-older-than 7d
```

### Garbage Collection

```bash
# Delete unused store paths
nix-collect-garbage

# Aggressive cleanup (delete old generations)
nix-collect-garbage -d

# Check what would be deleted (dry run)
nix-collect-garbage -d --dry-run

# Show store disk usage
nix-store --gc --print-dead | wc -l
```

### Store Optimization

```bash
# Optimize store (deduplicate)
nix-store --optimise

# Check store integrity
nix-store --verify --check-contents
```

---

## Homebrew Integration

```bash
# Homebrew is managed by nix-darwin
# Changes in default.nix casks/brews apply on rebuild

# Manual Homebrew operations (if needed)
brew list --cask           # List installed casks
brew list --formula        # List installed brews
brew cleanup               # Clean old versions
```

---

## Home Manager Commands

```bash
# Home Manager is integrated into darwin-rebuild
# No separate home-manager command needed

# To rebuild home config only (if standing alone)
home-manager switch --flake .#daniel@aegean

# Show home-manager generations
home-manager generations
```

---

## Services Management

### Yabai & skhd

```bash
# Restart services
yabai --restart-service
skhd --restart-service

# Stop services
yabai --stop-service
skhd --stop-service

# Check service status
launchctl list | grep yabai
launchctl list | grep skhd

# View yabai logs
tail -f /tmp/yabai_*.log
```

### SketchyBar

```bash
# Restart sketchybar
brew services restart sketchybar

# Stop sketchybar
brew services stop sketchybar

# Check status
brew services list | grep sketchybar
```

---

## Debugging & Troubleshooting

### Build Debugging

```bash
# Show full trace on error
darwin-rebuild switch --flake .#aegean --show-trace

# Verbose output
darwin-rebuild switch --flake .#aegean --verbose

# Keep build artifacts on failure
darwin-rebuild switch --flake .#aegean --keep-failed

# Show why a package is in the closure
nix why-depends /run/current-system nixpkgs#package-name
```

### Nix REPL

```bash
# Open Nix REPL with flake
nix repl
:lf .
:p darwinConfigurations.aegean.config.services

# Evaluate expression
nix eval .#darwinConfigurations.aegean.config.system.stateVersion
```

### System Information

```bash
# Show current system generation
ls -l /run/current-system

# Show activation script
cat /run/current-system/activate

# Check which profile is active
readlink /nix/var/nix/profiles/system
```

---

## Common Workflows

### Making Configuration Changes

```bash
# 1. Edit configuration files
vim hosts/aegean/default.nix

# 2. Test build
darwin-rebuild build --flake .#aegean

# 3. Apply if successful
darwin-rebuild switch --flake .#aegean

# 4. Commit changes
git add .
git commit -m "Update configuration"
```

### Updating System

```bash
# Full update workflow
nix flake update
darwin-rebuild switch --flake .#aegean
nix-collect-garbage -d
```

### Troubleshooting Failed Build

```bash
# 1. Show full trace
darwin-rebuild switch --flake .#aegean --show-trace

# 2. Check flake
nix flake check

# 3. Try building specific derivation
nix build .#darwinConfigurations.aegean.system

# 4. Rollback if needed
darwin-rebuild --rollback
```

---

## Advanced Commands

### Binary Cache

```bash
# Check if package is in cache
nix path-info --store https://cache.nixos.org nixpkgs#package

# Push to cache (if configured)
nix copy --to https://cache.example.com /nix/store/...
```

### Search Packages

```bash
# Search nixpkgs
nix search nixpkgs package-name

# Show package info
nix-env -qaP package-name
```

### Profile Management

```bash
# List profiles
nix profile list

# Install package to profile
nix profile install nixpkgs#package-name

# Remove from profile
nix profile remove package-name
```

---

## File Locations

```bash
# System configuration
/etc/nix/nix.conf

# Current system generation
/run/current-system

# System profile
/nix/var/nix/profiles/system

# User profile
~/.nix-profile

# Home Manager files
~/.config/home-manager

# Homebrew (managed by Nix)
/opt/homebrew
```

---

## Useful Aliases (Add to shell.nix)

```nix
home.shellAliases = {
  # Darwin rebuild shortcuts
  drb = "darwin-rebuild build --flake .#aegean";
  drs = "darwin-rebuild switch --flake .#aegean";
  drt = "darwin-rebuild build --flake .#aegean --show-trace";

  # Nix garbage collection
  ngc = "nix-collect-garbage -d";

  # Flake operations
  nfu = "nix flake update";
  nfc = "nix flake check";
};
```

---

## Tips

1. **Always commit changes before rebuild** - Flakes require Git tracking
2. **Use `--dry-run` to preview changes** - Safer than direct switch
3. **Keep old generations** - Easy rollback if something breaks
4. **Regular garbage collection** - Free up disk space
5. **Use `--show-trace` on errors** - Get full stack trace for debugging

---

## Quick Reference Card

| Task           | Command                                  |
| -------------- | ---------------------------------------- |
| Apply config   | `darwin-rebuild switch --flake .#aegean` |
| Test build     | `darwin-rebuild build --flake .#aegean`  |
| Update inputs  | `nix flake update`                       |
| Rollback       | `darwin-rebuild --rollback`              |
| Clean up       | `nix-collect-garbage -d`                 |
| Check config   | `nix flake check`                        |
| Restart yabai  | `yabai --restart-service`                |
| Restart skhd   | `skhd --restart-service`                 |
| View logs      | `darwin-rebuild switch --show-trace`     |
| Optimize store | `nix-store --optimise`                   |
