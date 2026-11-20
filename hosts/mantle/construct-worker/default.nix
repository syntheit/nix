# construct's pull worker for mantle (see ../construct-worker.nix). Call it from
# pkgs.pkgsCuda so faster-whisper's ctranslate2 is the CUDA build (the same
# one whisper.nix's whisper-ctranslate2 uses, from cache.nixos-cuda.org).
{ lib, python3Packages }:

python3Packages.buildPythonApplication {
  pname = "construct-worker";
  version = "0.2.0";
  pyproject = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./construct_worker
      ./tests
    ];
  };

  build-system = [ python3Packages.setuptools ];
  dependencies = with python3Packages; [
    faster-whisper
    requests
  ];

  # Offline tests (canned Ollama answers): python3 -m unittest discover -s tests
  nativeCheckInputs = [ python3Packages.unittestCheckHook ];
  unittestFlags = [
    "-s"
    "tests"
  ];

  pythonImportsCheck = [ "construct_worker.main" ];

  meta = {
    description = "construct job worker: memo transcription (faster-whisper), titles, chapters and tags (Ollama)";
    mainProgram = "construct-worker";
    platforms = lib.platforms.linux;
  };
}
