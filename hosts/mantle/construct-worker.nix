# construct's job worker (Memos): claims memos.transcribe and memos.title jobs
# from construct on raven (http://raven:4322 over the tailnet), every 15 s.
#   memos.transcribe: faster-whisper large-v3, float16, beam 5, VAD, word
#     timestamps, in a child process per job (the ~4.5 GB of VRAM is held only
#     while a memo transcribes; cancel = kill). Same CUDA package set as
#     whisper.nix, so the model in ~/.cache/huggingface is shared.
#   memos.title: a small model on the Ollama below, unloaded after each
#     request; an Ollama failure is a retryable job error.
#
# It stays off the GPU while it's someone else's: a foreign compute (CUDA)
# process over 1 GB of VRAM, or under ~5 GB of VRAM free (games are graphics,
# not compute), and the claim says busy (construct shows "mantle busy (GPU in
# use: …)"). Utilisation doesn't count: desktop graphics alone run 10-46%.
# After a failed job it pauses claims for 2 min, then 10. No GPU priority
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
  titleModel = "qwen3:4b-instruct-2507-q4_K_M";
in
{
  # Ollama on the GPU, for titles (and whatever else wants a local model). It
  # loads a model only on request; the worker asks with keep_alive 0. The
  # title model (2.5 GB) is pulled by ollama-model-loader after a switch.
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    loadModels = [ titleModel ];
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
      OLLAMA_MODEL = titleModel;
    };
    serviceConfig = {
      ExecStart = lib.getExe worker;
      # As daniel: whisper's model cache is his ~/.cache/huggingface.
      User = vars.user.name;
      Group = "users";
      Restart = "always";
      RestartSec = 10;
      Nice = 10;
      # SIGTERM to the worker only (the whisper child ignores it anyway), so it
      # can kill the child and hand the job back (release, no attempt used);
      # anything left gets SIGKILL after TimeoutStopSec.
      KillMode = "mixed";
      PrivateTmp = true;
      TimeoutStopSec = 30;
    };
  };
}
