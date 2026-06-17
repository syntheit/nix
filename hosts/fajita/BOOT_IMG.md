# fajita boot.img workflow

`nixos-rebuild switch` updates userspace only. Kernel/initramfs/cmdline live in
the **boot partition** as an Android-format boot.img — that doesn't get re-flashed
automatically. Whenever you change kernel-side config, you need to rebuild the
boot.img and flash it.

## When you need this

Any change to:
- `boot.kernelParams`
- `boot.kernelPatches`
- `boot.kernelModules` (only if the change affects the initramfs)
- `mobile.boot.stage-1.*`
- Kernel version (via `mobile-nixos` input bump)

Userspace-only changes (services, packages, dconf, udev rules, `environment.*`)
do **not** need this — `nixos-rebuild switch` alone is enough.

## Flash from running system

From a host that can build aarch64 (harbor, mantle with binfmt, or any nixos
host on the LAN):

```sh
# 1. Build
cd ~/nix
nix build .#nixosConfigurations.fajita.config.mobile.outputs.android.android-fastboot-images

# 2. (Optional but recommended) back up current boot_a
ssh daniel@fajita 'sudo dd if=/dev/disk/by-partlabel/boot_a of=/tmp/boot_a.backup bs=4M'

# 3. Push new boot.img
scp result/boot.img daniel@fajita:/tmp/boot-new.img

# 4. Flash to active slot (current is _a; check with `qbootctl -c` if unsure)
ssh daniel@fajita 'sudo dd if=/tmp/boot-new.img of=/dev/disk/by-partlabel/boot_a bs=4M conv=fsync && sync'

# 5. Reboot
ssh daniel@fajita 'sudo systemctl reboot'
```

## Recovery if the new boot.img breaks

The kernel boots before display init, so **ssh comes up even if display is
broken**. Tailscale, WiFi, USB-gadget all work — you have multiple paths in.

```sh
# Roll the boot partition back to the saved backup
ssh daniel@fajita 'sudo dd if=/tmp/boot_a.backup of=/dev/disk/by-partlabel/boot_a bs=4M conv=fsync && sync'
ssh daniel@fajita 'sudo systemctl reboot'
```

If even the kernel won't boot (very rare — would need a bad cmdline or panic
in early init), the A/B slot machinery rolls back to slot _b after the
bootloader's retry count expires (qbootctl marks slot good only at
multi-user.target; if we never reach that, the boot is "trying" and gets
rolled back). Worst case after both slots fail: USB fastboot recovery via
`fastboot flash --slot=a boot boot.img`.

## Why it works (1 paragraph)

The boot partition (`/dev/disk/by-partlabel/boot_a` → `/dev/sde11`, ~64 MB) holds a
binary blob in Android boot.img format: header + compressed kernel + initramfs +
DTB + cmdline. The Qualcomm aboot/ABL bootloader reads it from a fixed
partition offset, parses the header, loads the kernel into RAM with the
embedded cmdline, jumps in. `fastboot flash boot` from USB is just one way to
write that partition; `dd` from the running system is another, same wire
format. As long as the boot.img is correctly formatted (which `nix build` of
`mobile.outputs.android.android-fastboot-images` guarantees), the bootloader
doesn't care how it got there.

## Upstream gap to PR

Mobile NixOS could ship an `installBootLoader` hook that auto-flashes
`/dev/disk/by-partlabel/boot_${slot}` after `nixos-rebuild switch`. Standard
NixOS does the equivalent via `systemd-boot-install` / `grub-install`; Mobile
NixOS leaves it to the user. Closing this gap would make kernel-side changes
single-step and bring Mobile NixOS in line with the rest of NixOS.
