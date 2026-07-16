# aarch64 builds offload to the mini (Mac) — builder handoff

TL;DR: harbor no longer builds aarch64-linux locally. Every aarch64 derivation
(including the fajita kernel) auto-offloads over SSH to a native aarch64 NixOS VM
on the Mac mini. You don't do anything special — build fajita normally on harbor
and it goes to the Mac. It's native, not qemu.

## What changed / why
- Local qemu-user binfmt for aarch64 is DISABLED on harbor (hosts/harbor/hardware.nix).
  Heavy aarch64 builds (kernel, image codecs) were too slow or failed under qemu.
- harbor now has a nix build machine registered for aarch64-linux pointing at the
  mini's VM (hosts/harbor/nix-builder.nix: nix.distributedBuilds + /etc/nix/machines).

## The builder
- A native aarch64-linux NixOS VM (QEMU + hvf) on the mini, via nix-darwin's
  linux-builder mechanism, hand-rolled in hosts/mini/linux-builder.nix (Determinate
  Nix can't use the stock module). Sized 8 cores / 8 GiB / 100 GiB.
- Reached from harbor by SSH ProxyJump through the mini's real sshd:
  harbor -> daniel@mini:22 -> localhost:31022 -> guest VM. Direct-to-VM over
  Tailscale does NOT work (qemu slirp + 1280 MTU kills the SSH handshake), hence the
  jump. One key does both hops (sops secret mac_builder_ssh_key; its pubkey is
  authorized on daniel@mini, forwarding-only).

## How to use it (just build normally)
- Build fajita: `nixos-rebuild build --flake .#fajita` or
  `nix build .#nixosConfigurations.fajita.config.system.build.toplevel` — aarch64
  derivations offload automatically.
- Deploy to the phone: `nixos-rebuild switch --flake .#fajita --target-host
  daniel@fajita --sudo`, then reboot the phone. (harbor reaches fajita over Tailscale.)
- Confirm it's offloading: build logs show
  `building '...' on 'ssh-ng://builder@mac-linux-builder'...`, and
  `cat /etc/nix/machines` lists the builder.

## Gotchas (read these)
- The mini MUST be reachable. binfmt is off, so with the mini down, aarch64 builds
  FAIL outright ("a 'aarch64-linux' with features {} is required" / no machine) —
  there is no local fallback. The mini idles always-on.
- If a build can't reach the builder (the VM wedged once after a resize):
  `ssh mac 'sudo launchctl kickstart -k system/org.nixos.linux-builder'`, then wait
  ~10s and check `ssh mac 'nc -z localhost 31022 && echo up'`.
- DO NOT touch binfmt_misc on harbor by hand. Do not hand-register qemu binfmt
  handlers via /proc/sys/fs/binfmt_misc/register — a malformed magic/mask matches
  every ELF and recursively breaks ALL process exec on harbor (kernel ELOOP; only a
  reboot recovers it). If you ever need local aarch64 fallback, do it the declarative
  way: uncomment `binfmt.emulatedSystems = [ "aarch64-linux" ];` in
  hosts/harbor/hardware.nix and rebuild. Never via /proc.
- Do NOT `darwin-rebuild .#mini` without `git pull` on the mini first. The jump key
  on daniel@mini is currently applied imperatively; the declarative version is on
  main (just pushed). Rebuild the mini without pulling and it regenerates
  authorized_keys without the builder key -> offload breaks. (The mini also has an
  unrelated uncommitted common.nix change, so a rebuild there needs care.)

## Kernel builds
- The fajita kernel builds on the Mac VM's 8 native aarch64 cores — far faster than
  qemu and free of the qemu fork/exec failures. Just build fajita and watch it land
  on `ssh-ng://builder@mac-linux-builder`.

## Config (all committed on main)
- hosts/harbor/nix-builder.nix  — build machine + ProxyJump ssh_config + sops secret
- hosts/harbor/hardware.nix     — binfmt aarch64 disabled (commented, with note)
- hosts/mini/linux-builder.nix  — the VM (sizing, launchd daemon)
- hosts/mini/default.nix        — the jump key (authorizedKeys)
