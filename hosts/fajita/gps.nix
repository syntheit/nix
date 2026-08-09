# fajita GPS / GNSS — location for GNOME Maps via ModemManager + GeoClue2.
#
# HW path: SDM845 has no standalone GNSS chip. The Hexagon modem's QMI LOC
# service provides GNSS over QRTR (no /dev/gnss, no /dev/cdc-wdm). ModemManager
# (already running with --test-quick-suspend-resume) exposes it; GeoClue2
# (already pulled in by services.desktopManager.gnome) consumes it and feeds
# GNOME Maps. No kernel work — this is all userspace wiring.
#
# What actually works on this firmware (verified on-device 2026-07-16):
#   - Standalone GNSS ONLY. `mmcli -m0 --location-enable-gps-nmea/--gps-raw`
#     succeed; the modem streams NMEA and GeoClue calls Location.Setup(GPS_NMEA)
#     on demand when an app requests location.
#   - NO assistance data available, so every fix is a full cold-start TTFF:
#       * XTRA injection -> "Cannot inject assistance data: unsupported"
#         (firmware doesn't advertise SupportedAssistanceData; no "supported
#          assistance"/"assistance servers" line in `--location-status`).
#       * SUPL A-GPS (agps-msa/msb) -> "Failed to receive operation mode
#         indication" on enable.
#     This matches the broader SDM845-mainline situation (pmOS's XTRA/geoclue
#     A-GPS work never merged). Nothing in software fixes cold-fix time here;
#     it just needs open sky + patience for the first lock.
#
# So this module wires only the consumer side. GeoClue + ModemManager do the
# rest on demand; deliberately NO persistent `mmcli --location-enable` service
# (that would hold the GNSS radio hot -> battery drain; GeoClue enables/disables
# per active client).
{ pkgs, ... }:
{
  # GeoClue2 is already enabled by the GNOME desktop module (mkDefault true),
  # with the [modem-gps] and [network-nmea] sources on and supl.google.com set.
  # GNOME Maps (org.gnome.Maps) isn't in the default allow-list, so it would
  # otherwise fall back to the gnome-shell GeoClue *agent* for an interactive
  # prompt. That agent dialog is unreliable on GNOME Shell Mobile, so hard-allow
  # Maps to get location without depending on the prompt.
  services.geoclue2.appConfig."org.gnome.Maps" = {
    isAllowed = true;
    isSystem = false;
  };

  # qmicli for low-level GNSS/modem diagnostics (mmcli is already installed).
  environment.systemPackages = [ pkgs.libqmi ];
}
