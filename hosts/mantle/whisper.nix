# Speech-to-text on the 2070 Super: whisper-ctranslate2 (faster-whisper CLI)
# built against CUDA, wrapped as `transcribe` with sane defaults:
#   transcribe memo.m4a --output_dir out --initial_prompt "Hono, raven, asado"
# Any whisper-ctranslate2 flag overrides the defaults (argparse: last wins).
# large-v3 at float16 takes ~4.5 GB of the 8 GB VRAM; models download to
# ~/.cache/huggingface on first use. Benchmarked 2026-11-14: ~11x realtime,
# 2.5% WER on a TTS clip (the mini's whisper.cpp+VAD: ~5x, 4.4%).
#
# Runs at full speed, no throttling. If it ever makes the desktop lag, the
# lever is the CUDA timeslice, set only for the run (it's global, so leave
# it at Default for games):
#   nvidia-smi compute-policy --set-timeslice=1   (0 restores Default)
#
# pkgsCuda keeps CUDA per package (see modules/cuda-cache.nix). Checked
# 2026-11-14 against mantle's pin: the whole closure substitutes from
# cache.nixos-cuda.org (~8 GB, CUDA libs), nothing builds.
{ pkgs, ... }:
let
  whisper = pkgs.pkgsCuda.whisper-ctranslate2;
  transcribe = pkgs.writeShellApplication {
    name = "transcribe";
    runtimeInputs = [ whisper ];
    text = ''
      exec whisper-ctranslate2 \
        --model large-v3 --device cuda --compute_type float16 \
        --vad_filter True --language en "$@"
    '';
  };
in
{
  environment.systemPackages = [
    whisper
    transcribe
  ];
}
