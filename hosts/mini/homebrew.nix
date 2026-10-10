# Homebrew config for mini. Mirrors swift's cask list. Brews are kept minimal and reserved
# for things that genuinely need Homebrew's macOS-native build (e.g. ollama
# for Metal/GPU integration). CLI tools that have nixpkgs equivalents live in
# home.packages, not here.
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
      "karabiner-elements"
      "iina"
      "kiro"
      "ghostty"
      "lulu"
      "marta"
      "macwhisper"
      "notunes"
      "obsidian"
      "orbstack"
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
    ];
    brews = [
      "awscli-local"
      "ollama" # Kept in Homebrew for better macOS Metal/GPU integration
      "wifi-password"
    ];
  };
}
