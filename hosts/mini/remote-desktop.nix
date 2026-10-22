# Remote desktop host: Sunshine streams the mini's screen to Moonlight on
# mantle ("Mac mini" in the runner, hosts/mantle/mac-mini-desktop.nix).
#
# encoder = software: on macOS, Sunshine's VideoToolbox path (ffmpeg) adds
# ~120 ms of encoder latency (LizardByte/Sunshine#5441, 2026-09-22). libx264
# on the M4 does ~160 fps at 1440p superfast. YUV 4:4:4 would help photo
# editing, but 2026.516's macOS capture can't feed it ("Unsupported Pixel
# Format"); revisit when the ScreenCaptureKit capture (Sunshine#5511) lands.
#
# Audio stays on the mini's own speakers (stream_audio = disabled).
# Pairing state and the web UI login live in ~/.config/sunshine, outside Nix;
# the web UI only answers on localhost (origin_web_ui_allowed = pc).
{ pkgs, lib, vars, ... }:

let
  sunshine = "${pkgs.sunshine}/bin/sunshine";
in
{
  launchd.user.agents.sunshine = {
    serviceConfig = {
      ProgramArguments = [ sunshine ];
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardErrorPath = "/Users/${vars.user.name}/Library/Logs/sunshine.log";
    };
  };

  home-manager.users.${vars.user.name}.xdg.configFile."sunshine/sunshine.conf".text = ''
    sunshine_name = mini
    origin_web_ui_allowed = pc
    address_family = ipv4
    stream_audio = disabled
    encoder = software
    sw_preset = superfast
    sw_tune = zerolatency
    min_threads = 4
  '';

  matv.darwin.firewallAllowedApps = [ sunshine ];

  matv.darwin.tccGrants = [
    { service = "kTCCServiceScreenCapture"; package = pkgs.sunshine; exec = "sunshine"; reason = "Sunshine screen capture"; }
    { service = "kTCCServiceAccessibility"; package = pkgs.sunshine; exec = "sunshine"; reason = "Sunshine keyboard/mouse input"; }
    { service = "kTCCServicePostEvent"; package = pkgs.sunshine; exec = "sunshine"; reason = "Sunshine keyboard/mouse input"; }
  ];

  # A new sunshine store path gets its TCC grants in postActivation, after
  # launchd has already started the new binary, which then runs without
  # screen capture ("No screen capture permission!"). Restart it once the
  # grants exist, only when the binary changed so open streams survive
  # ordinary rebuilds.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    stamp=/var/db/nix-darwin/sunshine.path
    if [ "$(cat "$stamp" 2>/dev/null)" != "${sunshine}" ]; then
      # Its startup encoder probe hangs against a sleeping display.
      caffeinate -u -t 5 >/dev/null 2>&1 &
      sleep 1
      launchctl kickstart -k "gui/$(id -u ${vars.user.name})/org.nixos.sunshine" 2>/dev/null || true
      echo "${sunshine}" > "$stamp"
    fi
  '';
}
