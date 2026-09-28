# EQ for the TRUTHEAR x Crinacle Zero:RED IEMs on the front-panel jack.
#
# A PipeWire filter-chain attached as a WirePlumber "smart filter" to the
# onboard analog output: whenever that output is selected, audio goes through
# the EQ automatically, and the Mac mini speakers and HDMI are left alone.
# Pick the analog output as usual; never pick "Zero:RED EQ" itself. Nothing
# else plays through the analog output, so in practice this means "when the
# Zero:REDs are in" (a 3.5 mm plug carries no ID, so other headphones on the
# same jack would get it too).
#
# The tune is deliberately small. Stock plus the Bass+ adapter already sounds
# right; this only adds sub-bass weight. Per AutoEQ measurements from seven
# reviewers, the adapter adds +2.8 dB below 45 Hz but also leaks into the low
# mids (+2.0 dB at 125 Hz, +1.1 dB at 250 Hz). The shelf below adds +3 dB under
# ~50 Hz and fades to ~0 by 250 Hz, so the low mids stay where they are:
#
#   Hz          31.5    63   125   250
#   adapter     +2.8  +2.6  +2.0  +1.1
#   + this EQ   +5.8  +5.2  +2.9  +1.2
#
# Both filters are RBJ biquads, the same definition AutoEQ / Equalizer APO use,
# so the numbers port to the Mac as-is:
#   Preamp: -3.0 dB
#   Filter 1: ON LSC Fc 100 Hz Gain 3.0 dB Q 0.70
{ ... }:
let
  # Exact node.description of the onboard analog output, as `wpctl status`
  # prints it. WirePlumber matches smart-filter targets by exact value.
  frontPanel = "Starship/Matisse HD Audio Controller Analog Stereo";
in
{
  services.pipewire.extraConfig.pipewire."61-zero-red-eq" = {
    "context.modules" = [
      {
        name = "libpipewire-module-filter-chain";
        args = {
          "node.description" = "Zero:RED EQ";
          "media.name" = "Zero:RED EQ";
          "filter.graph" = {
            nodes = [
              # A 0 Hz high shelf is a flat gain: the same trick PipeWire uses
              # for AutoEQ's "Preamp:" line. -3 dB keeps the +3 dB shelf from
              # clipping.
              {
                type = "builtin";
                name = "preamp";
                label = "bq_highshelf";
                control = {
                  Freq = 0.0;
                  Q = 1.0;
                  Gain = -3.0;
                };
              }
              {
                type = "builtin";
                name = "bass";
                label = "bq_lowshelf";
                control = {
                  Freq = 100.0;
                  Q = 0.7;
                  Gain = 3.0;
                };
              }
            ];
            links = [
              {
                output = "preamp:Out";
                input = "bass:In";
              }
            ];
          };
          "audio.channels" = 2;
          "audio.position" = [
            "FL"
            "FR"
          ];
          "capture.props" = {
            "node.name" = "effect_input.zero_red_eq";
            "media.class" = "Audio/Sink";
            "filter.smart" = true;
            "filter.smart.name" = "zero-red-eq";
            "filter.smart.target" = {
              "node.description" = frontPanel;
            };
          };
          "playback.props" = {
            "node.name" = "effect_output.zero_red_eq";
            "node.passive" = true;
            "stream.dont-remix" = true;
          };
        };
      }
    ];
  };
}
