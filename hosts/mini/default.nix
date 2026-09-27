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
    ../../modules/numtide-cache.nix
    ../../modules/darwin/common.nix
    ./homebrew.nix
    # Native aarch64-linux builder VM (Mimick's image codecs, gtk4-rs apps,
    # anything Linux) without qemu-user emulation. Hand-rolled because
    # nix.linux-builder.enable requires nix.enable, which Determinate nix
    # forbids (it owns /etc/nix/nix.conf) — details inside.
    ./linux-builder.nix
    ./speaker.nix
  ];

  networking.hostName = "mini";

  matv.darwin.tccGrants = tccGrants;

  # harbor, vista and raven offload aarch64-linux builds to this mini's
  # builder VM, reaching it via ssh ProxyJump through this host (the VM's slirp
  # port isn't reliably reachable across Tailscale — see
  # hosts/harbor/nix-builder.nix). The jump authenticates with the VM's own
  # builder key; add its public half here, restricted to port-forwarding only
  # so it can do nothing but open the tunnel to the VM. Merges with the login
  # key set in modules/darwin/common.nix. Rotating the builder key means
  # updating this line and mac_builder_ssh_key in secrets/{harbor,vista,raven}.yaml.
  users.users.${vars.user.name}.openssh.authorizedKeys.keys = [
    ''restrict,port-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBTH8l3CLJK5SxnTBUYxZsWpA85+L7J3pqti8ZBQyarX builder@localhost''
    # swift's nix-daemon sends its aarch64-darwin builds to this Mac's own
    # nix-daemon (hosts/swift/mini-builder.nix). The key can do nothing but
    # speak the Nix daemon protocol: no shell, no forwarding.
    ''restrict,command="/nix/var/nix/profiles/default/bin/nix-daemon --stdio" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH8/c/gg4lDegspccXbKSYthFDT/WkLP2fAznRfNlj0W swift nix-daemon -> mini''
  ];

  # Appended after the nix.custom.conf lines in modules/darwin/common.nix
  # (types.lines); for a repeated key, the later line wins. Changes need a
  # daemon restart: sudo launchctl kickstart -k system/systems.determinate.nix-daemon
  environment.etc."nix/nix.custom.conf".text = lib.mkAfter ''
    # ssh-ng builders need the connecting user trusted (swift, above).
    extra-trusted-users = ${vars.user.name}

    # The rest was live on the mini but never committed; kept so a rebuild
    # doesn't drop it. builders-use-substitutes is for the Linux builder VM
    # (see linux-builder.nix).
    builders-use-substitutes = true
    download-attempts = 5

    # Serialize binary-cache connections. This mini only has Tailscale MagicDNS
    # (100.100.100.100) as its resolver, and it drops nix concurrent DNS lookups,
    # so parallel narinfo fetches during darwin-rebuild fail "Could not resolve
    # host cache.nixos.org" even though the macOS system resolver is fine. One
    # connection = one DNS query at a time = reliable. Serial-download slowdown is
    # negligible on this build-only host. (diagnosed 2026-08-20)
    http-connections = 1
  '';

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
