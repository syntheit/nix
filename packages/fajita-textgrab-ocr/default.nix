# fajita-textgrab-ocr — OCR helper for the long-press text-grab feature.
# Wraps the raw python script (PNG on stdin → word/line boxes JSON) so a
# private eng+spa tesseract5 build is on PATH with TESSDATA_PREFIX set at
# runtime — the shell's text-select gesture pipes a screenshot in and reads
# the JSON back.
{ writers, python3Packages, tesseract5, makeWrapper, lib, symlinkJoin }:
let
  tesseract = tesseract5.override { enableLanguages = [ "eng" "spa" ]; };
  raw = writers.writePython3Bin "fajita-textgrab-ocr-unwrapped" {
    libraries = [ python3Packages.pillow ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./fajita_textgrab_ocr.py);
in
symlinkJoin {
  name = "fajita-textgrab-ocr";
  paths = [ raw ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    rm -f $out/bin/fajita-textgrab-ocr-unwrapped
    rm -f $out/bin/fajita-textgrab-ocr
    makeWrapper ${raw}/bin/fajita-textgrab-ocr-unwrapped $out/bin/fajita-textgrab-ocr \
      --prefix PATH : ${lib.makeBinPath [ tesseract ]} \
      --set TESSDATA_PREFIX ${tesseract}/share/tessdata
  '';
  meta = {
    description = "OCR helper: PNG on stdin → word/line boxes JSON (tesseract eng+spa) for shell text-select";
    mainProgram = "fajita-textgrab-ocr";
  };
}
