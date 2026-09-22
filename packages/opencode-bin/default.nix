# opencode — upstream release binary, pinned.
#
# nixpkgs' source build of opencode 1.18.30/.31 crashes on every prompt
# ("undefined is not an object (evaluating 'a.name')" in SystemPrompt.environment,
# anomalyco/opencode#48645) while the official release binary works. Switch
# home/modules/opencode.nix back to pkgs.opencode once nixpkgs ships a build that
# passes: `opencode run "reply with pong"`.
#
# Bump: set `version`, then refresh each hash with
#   nix store prefetch-file --json <url> | jq -r .hash
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  unzip,
  ripgrep,
}:

let
  version = "1.18.32";
  base = "https://github.com/anomalyco/opencode/releases/download/v${version}";
  sources = {
    x86_64-linux = fetchurl {
      url = "${base}/opencode-linux-x64.tar.gz";
      hash = "sha256-MEbgQE/cYPuAMH56R4JLoHR3NkF4pNCbqoVISW3W1Ds=";
    };
    aarch64-darwin = fetchurl {
      url = "${base}/opencode-darwin-arm64.zip";
      hash = "sha256-+mQ/k0AcE1CNjVE3gOVM6cwBID1QERS+m4jWJAi4EB8=";
    };
  };
in
stdenv.mkDerivation {
  pname = "opencode-bin";
  inherit version;

  src =
    sources.${stdenv.hostPlatform.system}
      or (throw "opencode-bin: unsupported system ${stdenv.hostPlatform.system}");

  # Archives hold a single `opencode` file at the root.
  sourceRoot = ".";

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook
  ++ lib.optional stdenv.hostPlatform.isDarwin unzip;

  dontConfigure = true;
  dontBuild = true;
  # Bun single-file executable: the JS bundle is embedded in the binary, and
  # strip would throw it away.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode $out/bin/opencode
    wrapProgram $out/bin/opencode --prefix PATH : ${lib.makeBinPath [ ripgrep ]}
    runHook postInstall
  '';

  meta = {
    description = "AI coding agent for the terminal (upstream release binary)";
    homepage = "https://github.com/anomalyco/opencode";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
