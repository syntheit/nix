# construct's wardrobe cut-out worker: claims `wardrobe.cutout` jobs from
# construct on raven (http://raven:4322 over the tailnet) every 15 s, removes
# each garment photo's background (rembg, u2net, CPU onnxruntime), measures its
# colours (CIELAB k-means) and uploads the cut-out PNG. raven is a phone, so
# this runs here. ./wardrobe-cutout/cutout.py is a copy of construct's
# app/server/modules/wardrobe/worker/cutout.py (copied at b805911); that
# folder's env.nix pins the same u2net, so `--file` dry runs there and here
# measure alike. Copy it again when construct changes it.
#   journalctl -u wardrobe-cutout -f
# Dry run (no construct):
#   wardrobe-cutout --file shirt.jpg --out shirt.png
#
# Token: `construct worker-token vista` on raven (replaces vista's old one),
# stored as construct_worker_token in secrets/vista/construct-worker.yaml
# (vista + daniel), handed to the unit with LoadCredential.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  python = pkgs.python3.withPackages (p: [
    p.rembg
    p.numpy
    p.pillow
  ]);
  # rembg finds the model under REMBG_HOME and downloads nothing.
  u2net = pkgs.fetchurl {
    url = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx";
    hash = "sha256-jRDS87t1rjttUnx3lE/F59zZSymAnUenOaenKKkStJE=";
  };
  models = pkgs.runCommand "rembg-u2net" { } ''
    mkdir -p $out/models/u2net
    ln -s ${u2net} $out/models/u2net/u2net.onnx
  '';
  worker = pkgs.writeShellScriptBin "wardrobe-cutout" ''
    export REMBG_HOME=${models}
    exec ${python}/bin/python3 -u ${./wardrobe-cutout/cutout.py} "$@"
  '';
in
{
  environment.systemPackages = [ worker ];

  sops.secrets.construct_worker_token = {
    sopsFile = ../../secrets/vista/construct-worker.yaml;
    restartUnits = [ "wardrobe-cutout.service" ];
  };

  systemd.services.wardrobe-cutout = {
    description = "construct wardrobe cut-out worker";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    environment = {
      CONSTRUCT_URL = "http://raven:4322";
      CONSTRUCT_WORKER_HOST = "vista";
      CONSTRUCT_WORKER_TOKEN_FILE = "%d/token";
      # numba/pymatting (pulled in by rembg) and onnxruntime want a writable home.
      HOME = "/var/cache/wardrobe-cutout";
      XDG_CACHE_HOME = "/var/cache/wardrobe-cutout";
      NUMBA_CACHE_DIR = "/var/cache/wardrobe-cutout/numba";
    };
    serviceConfig = {
      ExecStart = lib.getExe worker;
      DynamicUser = true;
      LoadCredential = "token:${config.sops.secrets.construct_worker_token.path}";
      CacheDirectory = "wardrobe-cutout";
      Restart = "always";
      RestartSec = 30;
      Nice = 10;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };
}
