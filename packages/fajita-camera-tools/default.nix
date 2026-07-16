# fajita camera tooling — CAMERA_PLAN.md phase 2.
# fajita-focus: manual + contrast-AF control of the rear camera's lc898217xc
# VCM, capturing through libcamera's soft ISP. Needs `cam` (libcamera) on
# PATH — camera.nix installs the tuned libcamera-fajita alongside this.
{ writers, python3Packages }:
writers.writePython3Bin "fajita-focus" {
  libraries = [ python3Packages.numpy ];
  # W503 contradicts modern PEP8 (operators go at line starts now)
  flakeIgnore = [
    "E501"
    "W503"
  ];
} (builtins.readFile ./fajita-focus.py)
