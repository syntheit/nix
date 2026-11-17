# construct's job worker (Memos): claims memos.transcribe and memos.title jobs
# from construct on raven (http://raven:4322 over the tailnet), every 15 s.
#   memos.transcribe: faster-whisper large-v3, float16, beam 5, VAD, word
#     timestamps, in a child process per job (the ~4.5 GB of VRAM is held only
#     while a memo transcribes; cancel = kill). Same CUDA package set as
#     whisper.nix, so the model in ~/.cache/huggingface is shared.
#   memos.title: a small model on the Ollama below, pulled on first use and
#     unloaded after each request; falls back to the memo's first sentence.
#
# It stays off the GPU while it's someone else's: a foreign compute (CUDA)
# process over 1 GB of VRAM, and the claim says busy (construct shows "mantle
# busy (GPU in use)"). Utilisation doesn't count: desktop graphics alone run
# 10-46%, and they aren't compute contexts. No GPU priority
# tricks: the CUDA timeslice stays at Default (see whisper.nix). Logs:
#   journalctl -u construct-worker -f
# Dry runs (no construct):
#   construct-worker --once --file memo.m4a       (prints the result JSON)
#   construct-worker --once --title "some transcript"
#
# Token: `construct worker-token mantle` on raven, stored as
# construct_worker_token (secrets.nix).
{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  worker = pkgs.pkgsCuda.callPackage ./construct-worker { };
in
{
  # Ollama on the GPU, for titles (and whatever else wants a local model). It
  # loads a model only on request; the worker asks with keep_alive 0.
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  environment.systemPackages = [ worker ];

  systemd.services.construct-worker = {
    description = "construct job worker (memos: transcribe, title)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
      "ollama.service"
    ];
    path = [ config.hardware.nvidia.package.bin ]; # nvidia-smi
    environment = {
      CONSTRUCT_URL = "http://raven:4322";
      CONSTRUCT_TOKEN_FILE = config.sops.secrets.construct_worker_token.path;
      WORKER_HOST = "mantle";
      OLLAMA_URL = "http://127.0.0.1:${toString config.services.ollama.port}";
      OLLAMA_MODEL = "qwen3:4b-instruct-2507-q4_K_M";
    };
    serviceConfig = {
      ExecStart = lib.getExe worker;
      # As daniel: whisper's model cache is his ~/.cache/huggingface.
      User = vars.user.name;
      Group = "users";
      Restart = "always";
      RestartSec = 10;
      Nice = 10;
      PrivateTmp = true;
      TimeoutStopSec = 30;
    };
  };
}
