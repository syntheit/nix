# Homebrew config for mini. Mirrors swift's cask list minus karabiner-elements
# (the Keychron Q1 Pro's QMK firmware handles all keyboard remapping; no
# software remap is needed on this host). Brews are kept minimal and reserved
# for things that genuinely need Homebrew's macOS-native build (e.g. ollama
# for Metal/GPU integration). CLI tools that have nixpkgs equivalents live in
# home.packages, not here.
{ vars, ... }:

{
  nix-homebrew = {
    enable = true;
    user = vars.user.name;
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      # "zap" would also delete app data on cleanup; a cask rename or brew
      # migration once turned that into a full data wipe (2026-07-02, swift).
      cleanup = "uninstall";
      upgrade = true;
    };
    casks = [
      "affinity"
      "antigravity"
      "arc"
      "claude"
      "cursor"
      "dbeaver-community"
      "karabiner-elements"
      # "blackhole-2ch"  # existential.audio (162.241.218.190) is down; brew bundle has no
                         # per-URL timeout and hangs forever. Re-enable once the upstream
                         # is reachable, or install the .pkg from
                         # https://github.com/ExistentialAudio/BlackHole/releases
      "iina"
      "kiro"
      "ghostty"
      "lulu"
      "marta"
      "macwhisper"
      "notunes"
      "obsidian"
      "orbstack"
      "raycast"
      "royal-tsx"
      "seafile-client"
      "spotify"
      "syncthing-app"
      "tailscale-app"
      "telegram"
      "thunderbird"
      "transmission"
      "visual-studio-code"
      "vnc-viewer"
      "whatsapp"
      "windows-app"
      "windscribe"
      "zen"
      "zed"
    ];
    brews = [
      "awscli-local"
      "ollama" # Kept in Homebrew for better macOS Metal/GPU integration
      "wifi-password"
    ];
  };
}
