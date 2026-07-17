# fajita camera — Tier 0/1 implementation plan

Planned 2026-07-16 after a 10-agent research pass (verdicts in
`~/fajita-notes/camera.md` + memory `project_fajita_camera`). This document is
the working plan: we execute it phase by phase, each phase gated on the
previous one's acceptance criteria. Everything here is **userspace-only** —
every phase deploys with a plain `nixos-rebuild switch`, no boot.img reflash,
rollback is `nixos-rebuild --rollback` / previous generation.

**PROGRESS (2026-07-16): Phases 0-3 COMPLETE** — commits a61dddc / d0e188d /
3a11aee / 8a9edc6. Snapshot autofocuses autonomously on the rear camera.
Next: Phase 4 (real CCM — colors still muted), Phase 5 (Megapixels/flash),
Phase 6 (harbor darkroom), Phase 7 (front FoV). Upstream draft ready in
`~/fajita-notes/upstream/libcamera-af-feedback.md` (patch 10 + test report).

**PLAN REVISION (2026-07-17, post phase-5 bring-up):** Megapixels is OUT as
a user-facing app (Daniel verified: quality far below the tuned+AF Snapshot
path, desktop-shaped UI). Snapshot-centric from here: raw capture =
`cam --camera <rear-id> --stream role=raw --file=x.dng` (libtiff added to
libcamera-fajita); flash + full-res + warm screen-flash land in a
**Snapshot fork** (new item, replaces 5c); Phase 6 darkroom consumes
cam-produced DNGs. Phase-5 bring-up still paid for itself: 3 upstreamable
bug finds (libmegapixels 16-byte VFE stride, nix sysconfdir config
discovery, AE digital-gain black-out that persists across sessions —
likely bites every Sony-sensor phone). GOTCHA for all tooling: libcamera
camera INDICES are not stable across boots — select by DT path substring
(rear = i2c-bus@1/camera@10). Also: 3 hard SoC crashes today, all
camera-adjacent (camss power-domain fragility) → Tier-2 kernel item; no
rapid remote camera cycling.

**Goal (Tier 0/1):** autofocused, color-correct 20MP rear photos + properly
processed selfies + LED/screen flash + a harbor-side "darkroom" pipeline for
low-light shots. **Out of scope (Tier 2, planned separately):** IMX519/C-PHY
kernel work, hardware ISP, anything requiring a reflash.

---

## Ground rules (apply to every phase)

- **Isolation:** all camera config lives in a new `hosts/fajita/camera.nix`
  module (imported from `default.nix`), with vendored files under
  `hosts/fajita/camera/` (`patches/`, `tuning/`, `megapixels/`). No camera
  logic creeps into `default.nix`.
- **Scoped rebuilds, not world rebuilds:** patched libcamera is injected via
  `services.pipewire.package = pkgs.pipewire.override { libcamera = patched; }`
  (+ same for wireplumber and the explicit `libcamera` CLI in systemPackages) —
  NOT a global `nixpkgs.overlays` entry. A global overlay would rebuild
  pipewire → gnome-shell → the world under emulation. Scoped, the closure is
  libcamera + pipewire + wireplumber. Build on the mini's aarch64 builder
  (same route as mimick).
- **Evidence or it didn't happen:** every phase saves its proof (topology
  dumps, photos, timing numbers) to `~/fajita-notes/camera-tests/phase-N/`
  with a short `notes.md`. Before/after pairs for anything quality-related.
- **Scripts are packages:** anything beyond a one-liner becomes a proper
  derivation (`packages/fajita-camera-tools/`), shellcheck-clean bash or
  python3 with argparse + type hints. No loose scripts scp'd to the phone.
- **One commit per phase**, plain commit messages (no trailers), message
  documents the *why* like the rest of this repo.
- **Upstream posture:** we vendor patches with their provenance recorded
  (URL + commit hash in a comment) so we can rebase and report results
  upstream (patchwork thread for AF, pmaports for tuning).

**Version baseline (verified 2026-07-16):** fajita pin `nixpkgs-gnome49` ships
libcamera **0.7.0**, megapixels **2.1.0**, libmegapixels **0.2.3**, snapshot
**49.1**, postprocessd **0.3.0**. Harbor (main nixpkgs) ships darktable
**5.6.0** (has the AI raw-denoise module). The AF branch we vendor from
(`tui/libcamera` `millicam_af_6`) is based on **exactly v0.7.0** — cherry-picks
apply clean, no rebase needed.

**Research artifacts on disk** (`~/fajita-notes/camera-artifacts/`):
`pmaports/` (imx371/imx376/imx519 tuning YAMLs + APKBUILD),
`libcamera-af/` (patch 26241 mbox, v0.7.0 soft.mojom, ipu3 CDAF reference,
CDAF commit diff), `fajita-webcam/` (44 files: known-working media-ctl
pipelines + AF constants for this exact phone), `megapixels/`
(oneplus,enchilada.conf, pinephone-pro.conf, flash.c, camera.css).

---

## Phase 0 — Tooling + ground-truth survey

*Objective: see everything, touch nothing. Est: ½ day.*

**Tasks**
1. Create `hosts/fajita/camera.nix`; import from `default.nix`. Add packages:
   `v4l-utils` (v4l2-ctl, media-ctl), `libcamera` (cam CLI).
2. udev: `TAG+="uaccess"` for `video4linux` + `media[0-9]*` nodes (user is
   already in `video`; uaccess makes the portal/session ACL path solid).
3. Survey script `fajita-cam-survey` (packaged): dumps to a timestamped dir —
   `media-ctl -p` topology, `cam --list`, `cam --list-controls` per camera,
   `v4l2-ctl --list-ctrls` on every `/dev/v4l-subdev*`, subdev crop/selection
   rects, `ls -l /sys/class/leds/` (flash LED node names), kernel camera
   dmesg. Run it; commit output to `~/fajita-notes/camera-tests/phase-0/`.

**Acceptance criteria**
- `cam --list` enumerates 2 cameras (imx371, imx376).
- `v4l2-ctl --list-ctrls` on the lc898217xc subdev shows `focus_absolute 0-2047`.
- Exact flash LED sysfs names recorded (expected `white:flash`/`yellow:flash`).
- Topology dump matches the fajita-webcam recipe (csiphy1→csid→vfe path for
  rear, csiphy2 for front).

**Rollback:** revert camera.nix import. Zero risk.

---

## Phase 1 — Tuning files + working Snapshot baseline

*Objective: fix the all-black/purple-flash bug, establish quality baseline.
Est: ½ day + build time.*

**Tasks**
1. Vendor `imx371.yaml` + `imx376.yaml` from `camera-artifacts/pmaports/` into
   `hosts/fajita/camera/tuning/` (imx376's Ccm block is borrowed from a
   Samsung s5kjn1 — ship as-is now, replaced by our own in Phase 4; note this
   in a comment).
2. Build `libcamera-fajita = libcamera.overrideAttrs` with `postInstall`
   installing the YAMLs to `$out/share/libcamera/ipa/simple/`. Wire it via the
   scoped pipewire/wireplumber overrides (see ground rules). This override
   point is reused by Phase 3 (patches land in the same derivation).
3. Rebuild on mini builder, switch, reboot pipewire/wireplumber.
4. Baseline captures: Snapshot front + rear, daylight + indoor; `cam` CLI
   captures of the same scenes. Save to phase-1 evidence dir.

**Acceptance criteria**
- Snapshot opens both cameras repeatedly (no black/purple on reopen).
- Rear shows plausible color (borrowed CCM active); front has black-level fix.
- Baseline photo set saved — this is the "before" for Phases 3–6.

**Rollback:** drop the package overrides; stock libcamera returns.

---

## Phase 2 — VCM proof + `fajita-focus` CLI

*Objective: prove the lens moves; get manually-focused sharp photos today.
Est: 1 day.*

**Tasks**
1. Manual smoke test (from fajita-webcam recipe): stream rear camera, then
   `v4l2-ctl -d <lc898217xc subdev> --set-ctrl=focus_absolute=N` at
   0/512/1024/1536/2047 — confirm the image visibly refocuses.
2. Build `fajita-focus` (python3 + numpy, in `packages/fajita-camera-tools/`):
   - capture frames via `cam` (processed stream is fine for contrast metrics);
   - sharpness = Laplacian variance, green channel, 256×256 center ROI;
   - 3-phase hill-climb with fajita-webcam's proven constants: coarse sweep
     (~227-step increments), fine (±128, step 32), ultra-fine (±32, step 8),
     80 ms settle per move;
   - modes: `--set N`, `--sweep` (log sharpness curve), `--auto` (converge).
3. Evidence: focus-sharpness curve plot/CSV + near (30 cm) / far photos.

**Acceptance criteria**
- `--auto` converges on a near target and a far target in < 4 s, repeatably
  (±1 fine step across 5 runs).
- A manually-focused rear photo is visibly sharp where baseline was blurry.

**Notes:** `analogue_gain` defaults to 0 on these sensors (black frames) —
the tool must set sane exposure/gain if driving V4L2 directly. Front camera
has NO VCM — tool must refuse `--camera front` gracefully.

**Rollback:** tools are additive; remove from systemPackages.

**COMPLETED 2026-07-16 — two discoveries now binding on later phases:**
1. *CCI power constraint:* focus (any camera-block i2c) writes only work
   while a stream is active — this tree powers the pipeline only when
   streaming. All VCM writes are mid-stream; `--hold` re-asserts through
   gaps.
2. *CRASHDUMP hazard:* rapid pipeline start/stop cycles (~50 over 30 min)
   crashed the SoC into Qualcomm CrashDump mode. NEVER design measurement
   loops that cycle the pipeline; use one continuous stream per session.
Result: auto-AF converges in 8.2 s, dead-repeatable (382/382/382), proof
photos in camera-tests/phase-2/. The <4 s target was a bad estimate (28
measurements × 0.3 s); in-IPA AF (Phase 3) supersedes it.

---

## Phase 3 — Autofocus in Snapshot (libcamera AF overlay)

*Objective: real AF in the everyday camera app. Snapshot has zero manual
controls (verified), so AF must live inside libcamera's IPA — which is also
the architecturally right place. Est: 3a ~2 days, 3b ~3–5 days incl. tuning.*

**Phase 3a — manual focus plumbing**
1. `git format-patch` from `tui/libcamera` branch `millicam_af_6` (v0.7.0
   base): cherry-pick `4ba05039` (focus control = patchwork #26241). Optionally
   `5f010580` (manual exposure) + `b4fe4244` (AGC disable) — useful for later
   phases' calibration captures.
2. **Add our own guard patch:** the patch emits lens controls even when
   `lensInfoMap_` is empty → segfaults on VCM-less cameras. Our front camera
   has no VCM; without the guard Snapshot front = crash. One-line
   `if (!lensInfoMap_.empty())` fix, kept as a separate vendored patch and
   reported upstream on the patchwork thread.
3. Apply in the Phase-1 `libcamera-fajita` derivation (`patches = [...]`).
   nixpkgs re-signs IPAs in postFixup automatically — no signing work.
4. Verify: `cam --set-controls LensPosition=...` focuses; front camera still
   opens; pipewire path unaffected.

**Phase 3b — CDAF (the prize)**
1. Cherry-pick the CDAF chain: `684ec195` (sharpness field in SwIspStats +
   hill-climb Af algorithm), `4da3fec3` (focus-loss detection), `da42da56`
   (center-crop ROI, fewer phases), `3ac05187` (scan speed), `4312a90e`
   (reindent).
2. Enable `Af:` in our imx376 tuning YAML; confirm front (no lens) is a no-op.
3. Tune scan parameters on-device against near/far/low-light targets — we own
   the code, iterate freely. Measure the SwStatsCpu sharpness cost (CPU% at
   1080p preview) before/after.

**Acceptance criteria**
- Snapshot rear: point at near object → sharp < 2 s; refocuses on scene
  change (focus-loss detect); no oscillation in steady scenes.
- Snapshot front: works exactly as before (no crash, AF inert).
- Preview CPU overhead from sharpness stats < ~10% relative.
- Photo evidence vs Phase-1 baseline.

**Risks/fallbacks:** mojom ABI change is contained by the scoped override (the
whole pipewire closure rebuilds together). If CDAF proves unstable, ship 3a +
`fajita-focus` as the interim and keep tuning 3b — manual focus is already a
massive win. Report test results on the patchwork thread either way.

---

## Phase 4 — Real CCM (color calibration)

*Objective: colors that survive the "send to a friend" test. Our 0.7.0 simple
IPA has Ccm support (`ccm.cpp` verified present). Est: 1–2 days, iterative.*

**Tasks**
1. Print a 24-patch ColorChecker layout on mantle (acknowledge inkjet limits —
   "Rank B" accuracy is documented as attainable; a real chart is a ~$100
   upgrade if we care later).
2. Capture raw DNGs of the chart under (a) daylight ≈6500K, (b) indoor
   incandescent ≈2800K, (c) cool white LED ≈4000K — both sensors. Use
   Megapixels DNG or `cam` raw stream; fixed exposure via the Phase-3a manual
   controls.
3. Solve per-illuminant 3×3 CCMs least-squares (numpy script, runs on mantle;
   lives in `packages/fajita-camera-tools/`). Reference values from the
   standard ColorChecker sRGB table; sanity-check against a Pixel photo of the
   same scene.
4. Write fajita-specific `Ccm:` blocks (3+ color temps) into both tuning
   YAMLs, replacing the borrowed s5kjn1 matrix. Rebuild, compare.

**Acceptance criteria**
- Gray card renders neutral (channel means within ~5%).
- Skin tones look human in daylight + indoor shots.
- Side-by-side vs Pixel reference saved; delta obvious vs Phase-1 baseline.

**Risk:** known upstream AWB-oscillation-with-CCM issue — if we hit it, cap
per-channel AWB gains in tuning; the Apr 2026 AWB smoothing series is a
stretch cherry-pick.

---

## Phase 5 — Megapixels: fajita config, LED flash, warm screen flash

*Objective: the high-quality raw path + flash, both kinds. Est: 2–3 days.*

**5a — device config + postprocessing**
1. Write `oneplus,fajita.conf` (first one in existence) adapting
   `camera-artifacts/megapixels/oneplus,enchilada.conf` + the fajita-webcam
   pipeline facts: `Rear` = imx376, 2592×1940 SBGGR10, `Rotate: 270`, csiphy1
   pipeline links; `Front` = imx371, 4656×3496 SBGGR10, `Rotate: 90`,
   `Mirror: true`, csiphy2 links.
2. Install via `environment.etc."megapixels/config/oneplus,fajita.conf"` —
   `/etc/megapixels/config/` is search path #3, so **no package rebuild** for
   config iteration.
3. Add `megapixels` + `postprocessd` (already in nixpkgs) to systemPackages;
   wire postprocessd as the postprocessor (drop-in via
   `/etc/megapixels/postprocess.sh` or postprocessor.d).
4. GTK/GLES check: Adreno 630 supports GLES 3.2 vs the requested 2.0 — should
   just work; if the debayer context fights GTK's renderer, set
   `GSK_RENDERER=gl` for Megapixels only (wrapper).

**5b — rear LED flash**
1. `FlashPath: "/sys/class/leds/white:flash"` (exact name from Phase-0
   survey). Megapixels writes `1` to `<FlashPath>/flash_strobe`; kernel
   self-terminates the strobe.
2. udev rule making `flash_strobe` group-`video` writable (Megapixels writes
   sysfs directly; the torch extension's logind path doesn't apply here).

**5c — warm screen flash (our fork)**
1. `megapixels-fajita = megapixels.overrideAttrs` with a small vendored patch:
   `camera.css` `.flash` `#ffffff` → warm (start `#FFF1E0`, iterate on-device);
   parameterize the hardcoded brightness=100 (flash.c:116) if the full-blast
   white point looks clinical.
2. `FlashDisplay: true` on the Front camera block.
3. Robustness check: kill Megapixels mid-flash → brightness must restore
   (verify the save/restore path; patch if it can wedge).

**Acceptance criteria**
- Megapixels streams both cameras with correct orientation/mirroring.
- Burst capture → postprocessd JPEG lands in Pictures; DNGs retained with
  `save-raw` on.
- Rear capture in the dark fires the LED flash, exposure benefits visibly.
- Front dark-room selfie with warm screen flash: face lit, tone warm, not
  corpse-blue. Evidence photos saved.

**Watch item:** fajita-webcam docs claim imx371 is quad-Bayer — if front
stills from Megapixels show mosaic artifacts the debayer needs the 2×2
collapse; investigate then (Snapshot comparison tells us if it's real).

---

## Phase 6 — Harbor "darkroom" pipeline (DNG → AI denoise → gallery)

*Objective: computational photography via the homelab — the low-light
answer. Est: 2–3 days.*

**Design**
- **Phone:** Megapixels keeps raw bursts (`save-raw`); a systemd **user path
  unit** watches Pictures for new `.dng`, moves burst sets into
  `~/Pictures/darkroom-queue/<burst>/`; a oneshot syncs the queue to harbor
  over tailscale (rsync, retries via timer — queue survives being off-network).
- **Harbor** (`hosts/harbor/darkroom.nix`): path unit on the inbox; per burst:
  darktable-cli 5.6 with a committed `.dtstyle` — AI raw denoise
  (rawdenoise-nind) → exposure → our CCM/DCP → sharpen → JPEG q90. v2 option:
  pre-stack the burst (mean/mertens via a small opencv script) before
  darktable.
- **Return:** processed JPEG rsyncs back into the phone's `~/Pictures/`
  (appears in gallery). Immich ingestion is a documented v2 option (harbor
  already runs Immich; mimick on the phone would see them).

**Acceptance criteria**
- End-to-end (shutter → processed JPEG on phone) < 2 min on WiFi.
- Airplane-mode shots process automatically when connectivity returns.
- Indoor low-light before/after documented: burst+AI-denoise output vs
  straight Snapshot shot of the same scene.
- Service is boring: journald logs, no polling loops, survives reboots, inbox
  cleaned after success, failures leave the burst in place for retry.

---

## Phase 7 — Front FoV investigation (timeboxed: 1 day)

*Objective: understand (and if cheap, fix) the "very zoomed in" selfie — an
open bug across all distros. Best-effort; do not rabbit-hole.*

1. From Phase-0 data: subdev selection/crop rects on imx371 vs full active
   array; try `media-ctl` selection targets to full array.
2. Compare Megapixels full-res DNG FoV vs Snapshot preview FoV — if the DNG
   shows the full field, the crop is in soft-ISP scaling → precise upstream
   report with our data; if the DNG is cropped too, it's sensor
   readout/quad-Bayer → document and defer.
3. Exit with either a config fix or a filed upstream issue. Either counts as
   done.

---

## Risk register

| Risk | Phase | Mitigation |
|---|---|---|
| aarch64 build times under emulation | 1,3 | scoped overrides (no world rebuild) + mini native builder |
| AF patch segfault on VCM-less front cam | 3 | our guard patch, tested explicitly |
| CDAF oscillation / slow convergence | 3b | we own the constants; fallback = 3a manual + fajita-focus |
| CCM fiddly / printed-chart inaccuracy | 4 | iterate; reference-match vs Pixel; real chart if needed |
| AWB×CCM oscillation (known upstream) | 4 | gain caps in tuning; AWB smoothing series as stretch |
| Megapixels GL context on GTK 4.20/Adreno | 5 | GSK_RENDERER=gl wrapper; software render worst-case |
| flash_strobe permissions | 5b | dedicated udev rule |
| imx371 quad-Bayer artifacts | 5 | detect via Snapshot comparison; defer if cosmetic |
| pmOS tunes against libcamera 0.7.2 vs our 0.7.0 | 1 | YAML format v1 identical; verified fields exist in 0.7.0 |

## Definition of done (Tier 0/1)

Rear: autofocused, color-correct 20MP stills, LED flash, DNG bursts.
Front: framed/mirrored selfies with warm screen flash. Low light: harbor
darkroom output that's clearly better than device output. Everything
declaratively in the repo, evidence trail in `~/fajita-notes/camera-tests/`,
and at least two upstream contributions (AF patch test report, lens-guard
fix). Then we decide on Tier 2 (C-PHY/IMX519 kernel work) with confidence.
