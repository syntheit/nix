{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:

# Apple's SF Pro (Text, Display, Rounded, variable) and SF Mono, unpacked from
# the DMGs on developer.apple.com/fonts. The hashes change when Apple updates
# the downloads: refresh them with `nix-prefetch-url <url>`.
let
  dmg =
    name: sha256:
    fetchurl {
      url = "https://devimages-cdn.apple.com/design/resources/download/${name}.dmg";
      inherit sha256;
    };
in
stdenvNoCC.mkDerivation {
  pname = "apple-fonts";
  version = "2026-09-27";

  srcs = [
    (dmg "SF-Pro" "061907yaf0j502zqdfaripkw8912bh7nic0yys52sb7rn6wb72ln")
    (dmg "SF-Mono" "0ibrk9fvbq52f5qnv1a8xlsazd3x3jnwwhpn2gwhdkdawdw0njkd")
  ];

  nativeBuildInputs = [ _7zz ];

  # DMG → .pkg → Payload → Payload~ (cpio) → fonts. 7zz warns about the DMG's
  # trailing data, hence `|| true` on the outer layers.
  unpackPhase = ''
    runHook preUnpack
    mkdir fonts
    for src in $srcs; do
      work=$(mktemp -d)
      7zz x -y -o"$work/dmg" "$src" >/dev/null || true
      find "$work/dmg" -maxdepth 2 -name '*.pkg' -print0 |
        while IFS= read -r -d "" pkg; do 7zz x -y -o"$work/pkg" "$pkg" >/dev/null || true; done
      find "$work/pkg" -name Payload -type f -print0 |
        while IFS= read -r -d "" payload; do 7zz x -y -o"$work/p1" "$payload" >/dev/null || true; done
      find "$work/p1" -maxdepth 1 -type f -print0 |
        while IFS= read -r -d "" inner; do 7zz x -y -o"$work/p2" "$inner" >/dev/null || true; done
      find "$work" \( -name '*.otf' -o -name '*.ttf' \) -exec cp {} fonts/ \;
    done
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out/share/fonts/opentype fonts/*.otf
    install -Dm644 -t $out/share/fonts/truetype fonts/*.ttf
    runHook postInstall
  '';

  meta = {
    description = "Apple SF Pro and SF Mono fonts";
    homepage = "https://developer.apple.com/fonts/";
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
  };
}
