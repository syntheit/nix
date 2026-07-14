{ pkgs, ... }:
let
  # Upstream alsa-ucm-conf has NO OnePlus support: its generic sdm845 HiFi
  # verb includes the wsa881x codec sequences ("SpkrLeft COMP Switch" etc.),
  # amps fajita doesn't have — the 6T speaker is a TFA9894 on QUAT_MI2S and
  # everything else lives on the WCD934x. wireplumber therefore fails the
  # verb ("Failed to get the verb HiFi") and exposes only a Dummy Output.
  # (mobile-nixos ships an sdm845 UCM too, but only "OnePlus 6.conf" — never
  # matches our longname "OnePlus 6T".)
  #
  # ./ucm/ holds the sdm845-mainline fajita profile (what pmOS ships), locally
  # trimmed: no card-init/ctl-remap includes (exec /bin/rm — absent on NixOS),
  # and no Internal Speaker route — our kernel DT has no tfa9894 node, so the
  # QUAT_MI2S controls don't exist and any cset on them fails the whole verb.
  # => WORKS: headphones, both mics, call earpiece. NO loudspeaker until the
  # DT gains the amp node (kernel rebuild; CONFIG_SND_SOC_TFA989X already =m).
  # The longname match conf.d/sdm845/"OnePlus 6T.conf" wins over generic
  # sdm845.conf in the merged system ucm2 tree (ALSA_CONFIG_UCM2).
  fajitaUcm = pkgs.runCommand "fajita-alsa-ucm" { } ''
    mkdir -p "$out/share/alsa/ucm2/conf.d/sdm845" \
             "$out/share/alsa/ucm2/OnePlus/fajita"
    cp ${./ucm/fajita.conf}    "$out/share/alsa/ucm2/OnePlus/fajita/fajita.conf"
    cp ${./ucm/HiFi.conf}      "$out/share/alsa/ucm2/OnePlus/fajita/HiFi.conf"
    cp ${./ucm/VoiceCall.conf} "$out/share/alsa/ucm2/OnePlus/fajita/VoiceCall.conf"
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
