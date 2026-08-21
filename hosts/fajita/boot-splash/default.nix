# nixos-flake plymouth theme + matching stage-2 still for fajita's unified
# boot splash. The blue NixOS snowflake asset is `nix-snowflake.svg` from
# nixpkgs' `nixos-icons` (the classic blue-gradient flake, CC-BY licensed by
# the NixOS project) — rasterised here with resvg so plymouth's script plugin
# and ply-image both blit an identical crisp PNG. Nothing is vendored into the
# repo; the asset comes straight from nixos-icons.
#
# Outputs:
#   $out/share/plymouth/themes/nixos-flake/  — theme dir (script plugin)
#   $out/share/fajita-boot-splash/nix-snowflake.png — the same still, for the
#       stage-2 `ply-image` blit (see hosts/fajita/default.nix postBootCommands).
{
  runCommand,
  resvg,
  nixos-icons,
  plymouth,
}:

let
  # Blue NixOS snowflake (colour variant, not the white one).
  snowflakeSvg = "${nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
in
runCommand "fajita-nixos-flake-splash"
  {
    nativeBuildInputs = [ resvg ];
  }
  ''
    themeDir="$out/share/plymouth/themes/nixos-flake"
    mkdir -p "$themeDir"

    # Rasterise the blue flake at a generous fixed size; the .script scales it
    # DOWN at runtime to a fraction of the panel, so oversizing here only costs
    # sharpness headroom, never correctness. Transparent background so both the
    # script sprite and ply-image composite it over their own black clear.
    resvg --width 512 --height 512 \
      "${snowflakeSvg}" "$themeDir/nix-snowflake.png"

    # The stage-2 still is literally the same PNG.
    mkdir -p "$out/share/fajita-boot-splash"
    cp "$themeDir/nix-snowflake.png" "$out/share/fajita-boot-splash/nix-snowflake.png"

    # The script itself.
    cp ${./nixos-flake.script} "$themeDir/nixos-flake.script"

    # Theme manifest. ImageDir/ScriptFile are absolute store paths, exactly like
    # nixpkgs' own spinner/script themes; the NixOS plymouth module symlinks this
    # dir into /etc/plymouth/themes as-is for the stage-2 daemon. Heredoc body is
    # flush-left on purpose — plymouth's config parser wants unindented keys.
    cat > "$themeDir/nixos-flake.plymouth" <<EOF
[Plymouth Theme]
Name=NixOS Flake
Description=Animated blue NixOS snowflake (fajita unified boot splash)
ModuleName=script

[script]
ImageDir=$themeDir
ScriptFile=$themeDir/nixos-flake.script
EOF
  ''
