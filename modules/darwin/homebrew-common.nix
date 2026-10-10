# nix-homebrew + brew-bundle activation settings shared by swift and mini.
# Per-host cask/brew lists stay in hosts/<host>/homebrew.nix.
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
  };
}
