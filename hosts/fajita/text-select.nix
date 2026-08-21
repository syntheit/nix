# Select-any-on-screen-text → Copy — the two backend helpers for the shell's
# long-press text-grab gesture ("long-press → read text → Copy"). The shell
# resolver picks one per window (see ~/fajita-notes/text-select-copy.md):
#
#   • fajita-textgrab-atspi — exact-text path for native GTK/libadwaita apps.
#     Args: --pid --x --y --granularity; returns {text, boxes} in window-local
#     px, or {} to signal the shell to fall back to OCR. (hosts/fajita/textgrab-atspi/)
#
#   • fajita-textgrab-ocr — universal fallback (Firefox, Waydroid, images).
#     Reads a PNG (a screenshot of the region under the finger) on stdin and
#     returns word/line bounding boxes as JSON; the shell maps those boxes to
#     screen coords for the highlight + Copy pill. Bundles a private eng+spa
#     tesseract (tessdata in the store, no runtime download).
#     (packages/fajita-textgrab-ocr/)
#
# `ocrs` is the alternate on-device OCR engine (Rust/NEON, rendered-text
# accurate); kept in the closure so the shell can call it by path.
{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.callPackage ./textgrab-atspi { })              # AT-SPI exact-text backend
    (pkgs.callPackage ../../packages/fajita-textgrab-ocr { }) # OCR fallback backend
    pkgs.ocrs # alternate on-device OCR engine — aarch64 only (x86 AVX-512 build bug)
  ];
}
