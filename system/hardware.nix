{
  ...
}:
{
  # Hardware firmware
  hardware.enableAllFirmware = true;

  # Enable wireless regulatory database and set regulatory domain to Argentina
  # This enables all 5GHz channels available in Argentina
  hardware.wirelessRegulatoryDatabase = true;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom="AR"
  '';
}
