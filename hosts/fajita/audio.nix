{ pkgs, ... }:
let
  # Upstream alsa-ucm-conf has NO OnePlus support: its generic sdm845 HiFi
  # verb includes the wsa881x codec sequences ("SpkrLeft COMP Switch" etc.),
  # amps fajita doesn't have — the 6T speaker is a TFA amp on QUAT_MI2S and
  # everything else lives on the WCD934x. wireplumber therefore fails the
  # verb ("Failed to get the verb HiFi") and exposes only a Dummy Output.
  # pmOS audio works because it ships the sdm845-mainline alsa-ucm-conf fork,
  # which has a fajita-specific tree keyed on the card longname. Vendor just
  # that subset; it merges into the system ucm2 tree next to upstream's
  # (ALSA_CONFIG_UCM2 already points at the merged system path, and the
  # longname match "OnePlus 6T.conf" wins over the generic sdm845.conf).
  fajitaUcm =
    pkgs.runCommand "fajita-alsa-ucm"
      {
        src = pkgs.fetchFromGitLab {
          owner = "sdm845-mainline";
          repo = "alsa-ucm-conf";
          rev = "45cb4c634e534ddfb255e85162fe705f94a23015";
          sha256 = "1m1cq0v3d61hzacrg4awlvb3hsh43bxk9iwz8a7acskza82h4j4m";
        };
      }
      ''
        mkdir -p "$out/share/alsa/ucm2/conf.d/sdm845"
        cp -r $src/ucm2/OnePlus "$out/share/alsa/ucm2/OnePlus"
        ln -s ../../OnePlus/fajita/fajita.conf \
          "$out/share/alsa/ucm2/conf.d/sdm845/OnePlus 6T.conf"
      '';
in
{
  environment.systemPackages = [ fajitaUcm ];

  # pmOS's sdm845 wireplumber tuning: the Q6 DSP path wants S16LE/48k and
  # large periods; defaults cause xruns/silence.
  services.pipewire.wireplumber.extraConfig."51-qcom-sdm845" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "node.name" = "~alsa_input.*"; }
          { "node.name" = "~alsa_output.*"; }
        ];
        actions.update-props = {
          "audio.format" = "S16LE";
          "audio.rate" = 48000;
          "api.alsa.period-size" = 4096;
          "api.alsa.period-num" = 6;
          "api.alsa.headroom" = 512;
        };
      }
    ];
  };
}
