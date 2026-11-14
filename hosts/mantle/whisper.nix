# Speech-to-text on the 2070 Super: whisper-ctranslate2 (faster-whisper CLI)
# built against CUDA. Used for transcribing voice memos, e.g.
#   whisper-ctranslate2 memo.m4a --model large-v3 --device cuda \
#     --compute_type float16 --vad_filter True --language en
# large-v3 at float16 takes ~4.5 GB of the 8 GB VRAM. Models download to
# ~/.cache/huggingface on first use.
#
# pkgsCuda keeps CUDA per package (see modules/cuda-cache.nix). Checked
# 2026-11-14 against mantle's pin: the whole closure substitutes from
# cache.nixos-cuda.org (~8 GB, CUDA libs), nothing builds.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.pkgsCuda.whisper-ctranslate2 ];
}
