{
  pkgs,
  lib,
  vars,
  ...
}:

let
  tccGrants = import ./tcc-grants.nix { inherit pkgs; };
in
{
  imports = [
    ../../modules/darwin/common.nix
    ./homebrew.nix
    # Native aarch64-linux builder VM (Mimick's image codecs, gtk4-rs apps,
    # anything Linux) without qemu-user emulation. Hand-rolled because
    # nix.linux-builder.enable requires nix.enable, which Determinate nix
    # forbids (it owns /etc/nix/nix.conf) — details inside.
    ./linux-builder.nix
  ];

  networking.hostName = "mini";

  matv.darwin.tccGrants = tccGrants;

  # harbor offloads aarch64-linux builds to this mini's builder VM, reaching it
  # via ssh ProxyJump through this host (the VM's slirp port isn't reliably
  # reachable across Tailscale — see hosts/harbor/nix-builder.nix). The jump
  # authenticates with the VM's own builder key; add its public half here,
  # restricted to port-forwarding only so it can do nothing but open the tunnel
  # to the VM. Merges with the login key set in modules/darwin/common.nix.
  users.users.${vars.user.name}.openssh.authorizedKeys.keys = [
    ''restrict,port-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBTH8l3CLJK5SxnTBUYxZsWpA85+L7J3pqti8ZBQyarX builder@localhost''
  ];

  # Mac mini has no TouchID — no PAM hooks needed. Sudo works via password
  # as usual. (Magic Keyboard with TouchID would re-enable this; if you ever
  # add one, copy the two lines from hosts/swift/default.nix.)

  # fnState is not set here. The Keychron Q1 Pro in Mac mode sends Apple
  # consumer codes (brightness_down, mission_control, …) on the F-row
  # regardless of fnState — that pref only inverts Apple-keyboard behavior.
  # Karabiner-Elements (hosts/mini/home.nix) does the consumer-to-raw-F-key
  # remap so skhd's f1-f6 bindings fire, and remaps caps_lock → fn so the
  # fn-modifier bindings in skhdrc work too.

  services.skhd = {
    enable = true;
    package = pkgs.skhd;
    skhdConfig = builtins.readFile ./skhdrc;
  };
}
