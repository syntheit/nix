# Marble GNOME Shell theme — hue-based accent colours, applied via the
# User Themes extension (SHELL theme only: it ships theme/gnome-shell/, no
# gtk-3.0/gtk-4.0, so it does NOT touch `gtk-theme`).
#
# Built from Daniel's fork (github:syntheit/Marble-shell-theme, branch
# gnome-49-50-support), which adds GNOME 49/50 support and a --gnome-version
# flag. The upstream installer is Python-3-stdlib-only and hard-codes
# ~/.themes as its output root with no --destination — so we point HOME at a
# writable build dir and relocate the generated folders into the store.
#
# Define the theme in one place (see hosts/fajita/theme.nix): pick `accent`
# (or a custom `hue`) and `mode`; passthru.themeName maps that to the folder
# name the User Themes extension selects.
{
  lib,
  stdenvNoCC,
  python3,
  src,
  # ── the knobs ──────────────────────────────────────────────────────────
  accent ? "blue", # named colour from colors.json (red/yellow/green/blue/purple/gray)
  hue ? null, # custom hue 0-360; overrides `accent` when set
  name ? null, # theme name for a custom `hue` (installer defaults to hue<N>)
  mode ? null, # "dark" | "light" | null = build BOTH
  filled ? false, # more vibrant accent
  sat ? null, # saturation 0-250 (100 = stock)
  # Target GNOME Shell major. There is no running gnome-shell in the build
  # sandbox, so we force it — otherwise the 47../48.. style overlays are
  # silently skipped and the theme renders unstyled on GNOME 47+.
  gnomeVersion ? "49",
}:

let
  baseName =
    if hue != null then (if name != null then name else "hue${toString hue}") else accent;

  installArgs =
    (
      if hue != null then
        [ "--hue" (toString hue) ] ++ lib.optionals (name != null) [ "--name" name ]
      else
        [ "--${accent}" ]
    )
    ++ lib.optionals (mode != null) [ "--mode" mode ]
    ++ lib.optional filled "--filled"
    ++ lib.optionals (sat != null) [ "--sat" (toString sat) ]
    ++ [ "--gnome-version" gnomeVersion ];
in
stdenvNoCC.mkDerivation {
  pname = "marble-shell-theme";
  version = "49.0-unstable-2026-07-16";

  inherit src;

  nativeBuildInputs = [ python3 ];

  buildPhase = ''
    runHook preBuild
    export HOME="$NIX_BUILD_TOP/build-home"
    mkdir -p "$HOME"
    python install.py ${lib.escapeShellArgs installArgs}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/themes"
    cp -r "$HOME"/.themes/Marble-* "$out/share/themes/"
    runHook postInstall
  '';

  passthru = {
    # Accent base name; generated folders are Marble-<base>-<mode>.
    themeBaseName = baseName;
    # Folder name the User Themes extension selects, e.g. themeName "dark".
    themeName = m: "Marble-${baseName}-${m}";
  };

  meta = {
    description = "Marble GNOME Shell theme (hue-based accent) — GNOME 49/50 fork";
    homepage = "https://github.com/syntheit/Marble-shell-theme";
    license = lib.licenses.gpl3Plus;
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
