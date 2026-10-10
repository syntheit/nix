# Homebrew config for swift. Casks for GUI apps (signing, system extensions,
# kexts — things Nix can't cleanly handle on macOS). Brews are kept minimal
# and reserved for things that genuinely need Homebrew's macOS-native build
# (e.g. ollama for Metal/GPU integration). CLI tools that have nixpkgs
# equivalents live in home.packages, not here.
{ ... }:

{
  imports = [ ../../modules/darwin/homebrew-common.nix ];

  homebrew = {
    casks = [
      "affinity"
      "antigravity"
      "arc"
      "claude"

      "cursor"
      "dbeaver-community"
      "blackhole-2ch"
      "iina"
      "karabiner-elements"
      "kiro"
      "ghostty"
      "lulu"
      "marta"
      "macwhisper"
      "notunes"
      "obs"
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
      "windows-app"
      "windscribe"
      "zen"
    ];
    brews = [
      "awscli-local"
      "ollama" # Kept in Homebrew for better macOS Metal/GPU integration
      "wifi-password"
    ];
  };
}
