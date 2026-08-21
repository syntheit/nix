# fajita — open work, with context

You (an LLM in a future session) are picking up a Mobile NixOS port of the
OnePlus 6T (codename `fajita`, SoC Qualcomm SDM845). Daniel Miller is the
human you're working with. This file is the bridge between sessions: each
item below is something to ship later, with the context you need to pick it
up cold without re-deriving everything we already know.

**This file is NOT committed.** It lives in the working tree as a scratchpad.
Don't add it to git unless Daniel asks.

When Daniel points you at one of these issues, read this whole file once,
then drill into the specific section. **Read `BOOT_IMG.md` in the same
directory** too — kernel-touching items need the flash dance and it's
documented there.

---

## How this repo works

- **Flake**: `/home/matv/nix/flake.nix`. Daniel's monorepo for all his NixOS
  hosts (mantle/harbor/swift/raven/conduit/vista/ledger/fajita).
- **Host config**: `/home/matv/nix/hosts/fajita/default.nix` (~900 lines) +
  `hosts/fajita/home.nix` (home-manager).
- **Per-fajita packages**: `/home/matv/nix/packages/{alsa-ucm-fajita,
  hexagonrpc, q6voiced, mobile-config-firefox}/`.
- **Build host**: `harbor` (his home server, x86_64, aarch64-linux via
  qemu-user binfmt). You'll be running on harbor most of the time.
- **Phone**: reachable at `daniel@fajita` over Tailscale + WiFi. Passwordless
  sudo. The ssh config `Host fajita` is set up; just use `ssh daniel@fajita`.
- **Rebuild + push**:
  ```
  cd ~/nix && nixos-rebuild switch --flake .#fajita \
    --target-host daniel@fajita --elevate=sudo --use-substitutes
  ```
  Returning non-zero exit 4 is **fine** — it's the recurring
  `systemd-networkd-wait-online.service` warning on Phosh's startup; the
  actual switch landed. Confirm via `ssh daniel@fajita 'readlink /run/current-system'`.
- **Build-only**: `nix build .#nixosConfigurations.fajita.config.system.build.toplevel`.
- **Boot.img flash** (needed only for kernel/initramfs/cmdline changes): see
  `hosts/fajita/BOOT_IMG.md`. Don't conflate userspace rebuilds with this.

## Things to NEVER do without checking with Daniel

- Never run `nixos-rebuild test` style commands that boot a config without
  flashing — Mobile NixOS doesn't have that concept; you just build + activate.
- Never push with `--no-build-host` style flags unless he asks.
- Never add `Co-Authored-By: Claude` to commit messages. Use short lowercase
  imperative commit messages — match his style (`fajita: foo + bar`).
- Don't `nixos-rebuild boot` — there's no auto-flash, see BOOT_IMG.md.
- Don't run `nix-collect-garbage` on harbor without asking.

## What's already shipped (don't re-derive these)

You can read the actual config to see all of this, but high-level:
- Phosh + phoc + stevia OSK; scale=2.5; mobile-config-firefox userChrome
- Apps: Firefox, Brave, Chromium, Epiphany; Signal/Fractal/Chatty/Thunderbird
  /Vesktop; Clapper/Totem/VLC/Riff/Mousai/Delfin; Snapshot/Loupe/Papers
  /Nautilus/Resources/Mission-Center/Authenticator; the GNOME Circle set
  (Amberol, Blanket, Dialect, Fragments, etc.); Valent
- claude-code installed via home.packages
- Cellular: Claro AR APN profile
- SSH: Tailscale-only firewall (port 22 not open on WiFi)
- USB gadget: CDC-NCM, `172.16.42.1/24`, mantle sees `fajita.usb`
- Kernel param `msm.prefer_mdp5=0` (DPU driver, smoother than MDP5)
- GPU min_freq pinned 675 MHz via udev (smoothness)
- Suspend disabled (SDM845 mainline s2idle is broken)
- `pwrkey-wake-watcher.service` — uses wlr-randr to wake DPMS on power button
  press (SDM845 phoc-side wake bug)
- BT MAC derivation via `bluetooth-mac-fajita.service` (BT works now)
- Alert slider (3-state switch) → feedbackd Profile via systemd user service
- Persist partition mounted at `/mnt/vendor/persist` for sensor registry
- Phosh kept alive across rebuilds via `stopIfChanged=false`
- swclock-offset for RTC drift on first boot
- Avahi + CUPS
- Dark mode, blue accent, battery %, 12h clock

## Important gotchas you MUST know

1. **`GTK_IM_MODULE` must be `wayland`**. Something in nixpkgs (probably gnome
   default) pulls in `i18n.inputMethod.ibus` which sets `GTK_IM_MODULE=ibus`.
   That silently breaks Phosh OSK auto-show. The fix is in default.nix:
   `i18n.inputMethod.enable = lib.mkForce false` and `environment.{variables,
   sessionVariables}.GTK_IM_MODULE = lib.mkForce "wayland"`. Don't undo this.

2. **`scale = 2.5`** in `phocConfig.outputs.DSI-1`. Daniel chose this because
   it covers the OnePlus 6T notch (the 32px-hardcoded top bar grows to 80
   physical px, just enough). Don't change to 2.0 without his sign-off.

3. **Phosh dies on rebuild** without `stopIfChanged=false`. Daniel hated this.
   If you see phosh inactive after a rebuild, check that this is still set.

4. **The wallpaper is intentionally blurry**. Phosh 0.54 has a known bug
   where backgrounds render at logical px (432×936) then phoc upscales →
   bilinear blur. Daniel said he'll file an upstream Phosh MR for this.
   Don't touch the wallpaper config.

5. **Mobile NixOS doesn't auto-flash boot.img on rebuild**. Anything touching
   `boot.kernelParams`, `boot.kernelPatches`, kernel version, `initramfs`,
   or `mobile.boot.stage-1.*` needs the manual dance in `BOOT_IMG.md`.
   Userspace-only changes don't.

6. **The `exit-4` from nixos-rebuild** isn't real. It's
   `systemd-networkd-wait-online.service` complaining about Phosh starting.
   The activation actually succeeded — confirm with
   `ssh daniel@fajita 'readlink /run/current-system'` matching the build's
   output path.

7. **bitwarden-desktop / libreoffice / spotify / windscribe / zen-browser are
   intentionally NOT installed**. They were dropped for reasons (aarch64
   unavailable, electron-under-qemu-aarch64 too slow, touchscreen broken).
   Don't re-add without checking why they were dropped first — the comments
   in default.nix explain.

8. **There are memory files** at
   `/home/matv/.claude/projects/-home-matv-Projects-the-construct/memory/`.
   Read them. `project_fajita_osk_gotcha.md` and
   `project_fajita_smoothness_gotcha.md` capture two silent killers.

---

# Open issues

## #15 — KEY_POWER → phoc DPMS wake (root cause)

**Status**: workaround in place; root cause still unknown.

**Context**: SDM845 mainline has a phoc-side bug where pressing the power
button while DPMS is OFF doesn't wake the display. Phoc doesn't seem to
process input events while idle. Manifests as "I press power but the screen
stays black; I can ssh in but the UI is frozen for display."

**Workaround**: `systemd.services.pwrkey-wake-watcher` in default.nix watches
`/dev/input/event0` for KEY_POWER. On press, if
`/sys/class/drm/card*-DSI-1/dpms` reads `Off`, it runs `wlr-randr --output
DSI-1 --on` as daniel via sudo. Phosh wakes cleanly.

**What a real fix would look like**:
- Either patch phoc to consume input events even when DPMS-off, OR
- Find why libinput doesn't deliver KEY_POWER to phoc when idle
- Likely needs phoc upstream MR to gitlab.gnome.org/World/Phosh/phoc

**How to test the workaround still works**:
1. ssh in (so you have a recovery path)
2. Press the power button — display blanks
3. Press it again — display should come back without your intervention
4. If it doesn't, check `systemctl status pwrkey-wake-watcher` and the
   journal for the watcher

**Files**: `default.nix` around `pwrkey-wake-watcher`.

## #16 — Phosh top-bar dynamic height MR

**Status**: Daniel is working on this himself, upstream Phosh.

**Context**: `PHOSH_TOP_BAR_HEIGHT = 32` is hardcoded in
`phosh/src/top-panel.h`. Phones with notches taller than 32 logical px see
the notch poke through the bar. We worked around this by setting `scale=2.5`
so 32 logical = 80 physical and the OnePlus 6T notch is fully covered.

**Real fix**: upstream MR making `PHOSH_TOP_BAR_HEIGHT` derive from gmobile's
cutout bounds (the gmobile `oneplus,fajita.json` has the notch SVG path).

**Don't action this**: Daniel said he'll handle.

## #17 — USB OTG / FUSB302 DT binding

**Status**: kernel-level work, no clean Nix fix.

**Context**: SDM845 mainline kernel hardcodes `dr_mode = "peripheral"` in
`arch/arm64/boot/dts/qcom/sdm845-oneplus-common.dtsi` line ~617:
> /* We don't have the capability to switch modes yet. */
> dr_mode = "peripheral";
> maximum-speed = "high-speed";

This means USB-C port is gadget-only. Plugging in a USB-C keyboard does
nothing. We use this to do ssh-over-USB (CDC-NCM gadget), so we can't just
flip to `dr_mode = "host"` and lose that.

**Real fix**: kernel DT patch adding the FUSB302 type-c controller node +
`usb-connector { usb-c-connector }` + `usb-role-switch` wiring to
`&usb_1_dwc3`. The FUSB302 is at I2C bus 16 or 17 on fajita; downstream
Android DT extraction needed for IRQ/regulator pinning. Reference: sm8350
DTS pattern at https://lkml.iu.edu/2406.3/00645.html.

**Effort**: real kernel work, multi-hour. pmOS doesn't have this either —
their wiki marks OTG as not-working on fajita. So you'd be doing original
kernel work; bring evidence (downstream DT) and aim for upstream MR.

**Test approach**: after the kernel patch, `cat /sys/class/usb_role/*/role`
should appear; `cat /sys/class/typec/port0/data_role` should report `device`
with `[host]` available; plugging a USB-C keyboard should flip to `host`.

## #22 — Sensors phase 2: libssc + patched iio-sensor-proxy

**Status**: biggest remaining capability gap. Persist partition is mounted
(phase 1 done), hexagonrpcd serves the SLPI registry, SLPI publishes QMI
SNS_CLIENT_SVC. But stock `iio-sensor-proxy` can't read QMI; needs pmOS's
libssc-patched fork.

**Why**: Mainline SDM845 doesn't have an in-kernel IIO driver for the
Qualcomm Sensor Manager (Yassine Oudjana's `qcom_smgr` patchset is on LKML,
not merged). So the bridge has to be in userspace: libssc reads QMI, the
patched iio-sensor-proxy speaks libssc, exposes via DBus.

**What needs to happen**:
1. Package `postmarketOS/libssc` (GitLab) as a NixOS derivation.
2. Vendor pmOS's iio-sensor-proxy variant from
   https://gitlab.com/postmarketOS/pmaports/-/merge_requests/4050 — read
   their `aports/main/iio-sensor-proxy/` patches.
3. Add to fajita's overlay so the standard `services.hardware.sensor.iio.enable
   = true` flow picks up the patched binary.
4. Verify on the phone with `monitor-sensor` — should report accel + light
   + proximity.

**Once it works**:
- Phosh auto-rotation enables itself (uses `net.hadess.SensorProxy` over DBus)
- Proximity-off-during-call works (gnome-calls reads same DBus)
- Auto-brightness works (gsd-power uses the ALS reading)
- `gsettings set org.gnome.settings-daemon.peripherals.touchscreen
   orientation-lock false` to actually enable rotation

**Watch for**:
- libssc has Alpine-isms (apk/musl assumptions in build); patch as needed
- The patched iio-sensor-proxy creates virtual IIO devices, not real ones;
  make sure stock `hardware.sensor.iio.enable` doesn't conflict
- Test BMI160 accel direction (orient matrix in
  `/mnt/vendor/persist/sensors/registry/registry/bmi160_0_platform.orient`)
  — fajita has a known rotation-axis flip vs other SDM845 phones

**References**:
- pmOS wiki: https://wiki.postmarketos.org/wiki/Qualcomm_Snapdragon_Sensor_Core
- LKML qcom_smgr v2: https://lkml.org/lkml/2025/7/21/607
- pmaports MR !4050 (the patched binaries)
- hexagonrpc upstream: https://github.com/linux-msm/hexagonrpc

**Estimate**: multi-hour. The fiddly part is the libssc package, not the
proxy patches.

## #23 — Camera quality (libcamera IPAs)

**Status**: cameras work (Snapshot opens, all 3 enumerate via libcamera/
pipewire-camera), but look horrible — wrong colors, no AWB, no exposure
control.

**Context**: Snapshot uses libcamera, which needs **IPAs** (Image Processing
Algorithms) per sensor model. Mainline libcamera doesn't ship IPAs for
IMX519, IMX376, IMX371. pmOS has been working on this for years.

**Sensors on fajita**:
- IMX519 (rear main wide, 16MP, i2c-16 @ 0x1a)
- IMX376 (rear tele, 20MP, i2c-17 @ 0x10)
- IMX371 (front, 16MP, i2c-16 @ 0x10)

**What's needed**:
1. Check pmaports for any libcamera IPA work for SDM845 sensors. If they
   exist, vendor those.
2. Alternative: bypass libcamera entirely and ship megapixels with a real
   fajita config (which we built but didn't ship — see git history for
   "Megapixels fajita config (3 cameras)" research result, has draft).
3. The `qcom-camss` ISP is the bridge; calibration matrices may help even
   without per-sensor IPAs.

**Daniel said "another day"** — but if you're picking this up, his
expectation is:
- Better colors (not magenta/green-shifted)
- Working autofocus (uses lc898217xc on i2c-16 + i2c-17)
- All three cameras selectable via the UI

**Files to look at if you start**:
- `nixpkgs.libcamera` derivation (does it include IPAs?)
- mobile-nixos camera support (probably nothing fajita-specific)
- pmaports `community/libcamera-tools` etc.

**Test rig**: open Snapshot, try each camera. Compare against reference
(your iPhone or a normal Android camera). Look for color cast and exposure
clipping. If photos are unusable, vendor megapixels config as a backup.

## #9 (now done) — swclock-offset

Done. Mentioned for context: there's a systemd pair —
`swclock-offset-save.service` (saves time at shutdown to
`/var/lib/swclock-offset/last`) and `swclock-offset-restore.service`
(restores at boot, before time-sync.target). Test by `sudo systemctl stop
swclock-offset-save` then check the file exists.

---

# Upstream PR opportunities (anytime)

These aren't open issues, but they're real contributions Daniel could make.
Mention them when relevant.

## A. mobile-nixos sdm845 family module

The fajita config has multiple fixes that benefit any SDM845 phone (enchilada,
beryllium, polaris, etc.). These should be PR'd to
`mobile-nixos/mobile-nixos` as a refactor to its `families/qualcomm-sdm845/`
module:

1. **GPU min_freq pin udev rule** — Adreno 630 simple_ondemand is too lazy;
   pin to 675 MHz. (see `default.nix` `services.udev.extraRules`)
2. **`msm.prefer_mdp5=0` kernel param** — DPU > MDP5 for animation smoothness
3. **fastrpc devnode permissions** — udev rule giving group `fastrpc` rw
4. **Persist partition mount** — `/mnt/vendor/persist` for SLPI registry
5. **BT MAC derivation pattern** — every SDM845 OnePlus has this WCN3990
   placeholder-BD-address issue

Look at the current mobile-nixos `families/qualcomm-sdm845/default.nix` (if
it exists) and propose adding these.

## B. nixpkgs `hexagonrpc` package: ship fastrpc udev rules

Currently we add the udev rules in fajita's host config:
```
KERNEL=="fastrpc-adsp", GROUP="fastrpc", MODE="0660"
KERNEL=="fastrpc-sdsp", GROUP="fastrpc", MODE="0660"
KERNEL=="fastrpc-cdsp", GROUP="fastrpc", MODE="0660"
```
These belong in nixpkgs's `hexagonrpc` package itself (`postInstall` or via
`udevRules` attr). PR to NixOS/nixpkgs.

## C. Phosh top-bar dynamic height

Daniel is doing this.

## D. Phosh wallpaper buffer_scale

Daniel is doing this. Sketch: in `phosh/src/background.c`, the
`phosh_utils_pixbuf_scale_to_min(pixbuf, w, h)` call uses w/h from
`phosh_layer_surface_get_configured_width/height()` which are surface-local
(logical) pixels. Should be multiplied by `gdk_window_get_scale_factor` (or
the layer surface's buffer scale) before sizing the pixbuf, AND
`wl_surface.set_buffer_scale` should be called.

## E. Mobile NixOS `installBootLoader` hook

Currently `nixos-rebuild switch` updates userspace but doesn't flash boot.img.
Mobile NixOS could ship an `installBootLoader` script that writes the
generated boot.img to `/dev/disk/by-partlabel/boot_${slot}` after activation.
Same way standard NixOS calls grub-install / systemd-boot-install.

Sketch:
```nix
system.build.installBootLoader = pkgs.writeShellScript "mobile-install-boot" ''
  slot=$(qbootctl -c | awk '{print $NF}')
  dd if=${config.mobile.outputs.android.android-fastboot-images}/boot.img \
     of=/dev/disk/by-partlabel/boot_$slot bs=4M conv=fsync
'';
```

Test: after `nixos-rebuild switch` with a kernel param change, reboot — new
param should be effective without manual scp + dd.

---

# Refactor: extract `modules/oneplus-fajita/`

This is an organizational project, not a behavior change. Daniel keeps
mentioning it.

**Goal**: separate "device support for OnePlus 6T" from "Daniel's personal
config" so that:
- Someone else can `imports = [ ./modules/oneplus-fajita ]` and get a working
  phone without inheriting Daniel's Tailscale account / Claro APN / dotfiles.
- The repo becomes shareable as a reference for SDM845-on-NixOS folks.
- Upstream PRs are easier to extract (you copy the module wholesale).

**What goes in the module (~600 lines of current `default.nix`)**:
- libinput overlay
- Firmware path remap (oneplus6 → OnePlus/enchilada)
- Stage-1 firmware
- mobile.quirks.qualcomm.sdm845-modem
- ModemManager `--test-quick-suspend-resume`
- USB gadget service
- systemd-networkd usb0
- Phosh + phocConfig.outputs.DSI-1.scale=2.5
- Suspend disabled + logind settings
- pwrkey-wake-watcher
- bluetooth-mac-fajita
- alert-slider-handler
- persist mount
- swclock-offset
- GPU pin udev + fastrpc udev + volume-keys-no-wake
- mobile-config-firefox userChrome
- ALSA UCM, q6voiced, hexagonrpc
- DPU kernel param
- pmOS-defaults env (Qt mobile, GTK_IM_MODULE=wayland, dconf gtk-im-module)
- Watchdog disable

**What stays in `hosts/fajita/default.nix`** (Daniel's personal):
- Tailscale
- Claro APN
- Daniel's user + SSH key + groups
- Personal app list (`environment.systemPackages` for browsers, GNOME apps,
  etc. — though arguably some are device-support)
- dconf wallpaper + accent + clock-format
- `programs.firefox.preferences` (his choices)
- nix-related settings (auto-optimise-store, gc, trusted-users)
- ssh allowedKeys
- time.timeZone

**Watch for**:
- mkForce conflicts — some module options use mkForce in default.nix;
  splitting them across modules can cause re-binding issues
- Don't break the boot.img generation — the kernel/initramfs config lives
  via the `mobile-nixos` flake input + `device = "oneplus-fajita"`. The
  module just adds NixOS-level stuff on top.
- Test after refactor: build, no diff in `nix path-info` between before/
  after refactor (within reason). Use `nix store diff-closures` to verify
  near-identical output.

**Estimate**: 30-60 min focused. Mechanical. Daniel will appreciate it.

---

# How to test things

These are common verifications. Adapt per task.

- **System landed**: `ssh daniel@fajita 'readlink /run/current-system'` should
  match `nix path-info .#nixosConfigurations.fajita.config.system.build.toplevel`.
- **Phosh alive**: `ssh daniel@fajita 'systemctl is-active phosh'` returns
  `active`.
- **BT works**: `ssh daniel@fajita 'hciconfig hci0 | head -3'` shows
  `UP RUNNING` and a non-placeholder BD address.
- **Alert slider**: `ssh daniel@fajita 'systemctl --user --machine=daniel@.host
  status alert-slider-handler'` shows active running. Daniel flips the
  switch, checks Phosh ringer state.
- **Sensors**: `ssh daniel@fajita 'ls /sys/bus/iio/devices/'` — only PMIC
  devices means phase 2 still needed. Real sensors appear as more entries.
- **DPMS wake**: power button presses, see if display comes back without
  ssh-rescue.
- **Phosh-dies-on-rebuild**: do a rebuild, then immediately check
  `systemctl is-active phosh`. Should stay `active`.
- **GTK_IM_MODULE**: `ssh daniel@fajita 'cat /proc/$(pgrep libexec/phosh |
  head -1)/environ | tr "\0" "\n" | grep GTK_IM'` — must be `wayland`.

---

# Asking Daniel for things

- He's terse. Don't pad responses.
- Don't add "I'll continue with X" or "Let me know if Y" filler.
- When you've made a decision (e.g. "drop bitwarden-desktop because aarch64
  unavailable"), say what you did + why, not a list of options.
- Use shared memory files (`~/.claude/projects/...`) — read them at session
  start, write to them when you learn something durable about him or about
  fajita.
- Argentine Spanish if he writes in Spanish.
- Don't sign-off with motivational lines.
