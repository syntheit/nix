# conduit switchboard

Config: `hosts/conduit/switchboard.nix` (options) and `hosts/conduit/headscale.nix` (consumers).
Defaults: every service -> vista (10.100.0.4), no NUC peer. With defaults the conduit toplevel is
byte-identical to main 52abc28 (`/nix/store/h4w17rzz...-nixos-system-conduit-26.11.20261023.3ec6363`).

## Options (`malli.conduit.*`)
- `nucWgAddress` (default "10.100.0.5"), `nucWgPublicKey` (default null = no NUC peer)
- `upstream.<svc>` = "vista" | "nuc", default "vista":

| option | port | what it moves |
|---|---|---|
| headscale | 8085 | Caddy headscale.matv.io |
| deus | 8086 | Caddy bootstrap.matv.io /ade/bootstrap-creds + /healthz; socat :8086 (100.64.0.1 fleet and the 10.100.0.1 hairpin are the same listener, so they cannot split) |
| bootstrapPkg | 8088 | Caddy bootstrap.matv.io /pkg/* |
| git | 9418 | socat |
| registry | 5000 | socat |
| zot | 5001 | socat |
| operatorSsh | 2222 | socat |
| nanomdm | 9990 | Caddy mdm.matv.io + socat :9990 (incl. 10.100.0.1 hairpin; one listener) |
| scep | 8081 | Caddy scep.matv.io |
| mdmenroll | 9991 | Caddy enroll.matv.io |

## Flip / rollback
Flip: set e.g. `malli.conduit.upstream.git = "nuc";` in `hosts/conduit/default.nix`, redeploy conduit.
Rollback: set it back to "vista" (or delete the line) and redeploy. Same for every service.
First, once: set `malli.conduit.nucWgPublicKey = "<NUC pubkey>";` and redeploy (adds the peer).
Remove the key and redeploy to remove the peer.

## Services that must move together
- Hard: none enforced in code.
- Practical (all live in vista's headscale nspawn and share its state): `headscale` + `deus` (deus uses the
  headscale CLI/socket and deus's DB) ; `git` follows `deus` (deus reads the mirror); `bootstrapPkg` and
  `operatorSsh` are the same nspawn, move with them. Move as one group, or accept deus-on-X with headscale-on-Y only if deus can reach headscale remotely (it cannot today).
- `nanomdm` + `scep` (nanomdm reads the SCEP CA cert); `mdmenroll` is stateless and may go with them or alone.
- `deus` and `nanomdm` are independent: deus on NUC reaches nanomdm via the 10.100.0.1:9990 hairpin and the
  nanomdm webhook posts to 10.100.0.1:8086, so each follows its own flip.
- `registry`, `zot` independent.

## Reload behaviour
- Each socat is its own unit: a switch restarts only units whose ExecStart changed; other services keep
  their connections. A flipped socat drops only its own open connections (Macs reconnect).
- Caddy is reloaded in place (nixpkgs `enableReload`), not restarted; new requests use the new upstream. In-flight long
  streams on changed handlers (headscale long-polls) may be cut at reload; clients retry. Not tested live.
- NUC peer is a separate oneshot (`wg-nuc-peer`, `wg set wg0 peer ...`), not part of `networking.wg-quick`,
  because wg-quick-wg0 has no reload and any change to it restarts wg0 (drops harbor, vista, all relays).
  Verified: the wg-quick-wg0 unit file is unchanged by enabling the peer. If wg-quick-wg0 restarts for another
  reason, the peer unit is PartOf it and is re-run.

## Caveats
- Proof (built, not deployed): defaults identical. Test (git=nuc + dummy key): only `git-mirror-proxy.service`
  differs, plus new `wg-nuc-peer.service`; Caddy config unchanged.
- Data is not moved by this; flip only after the NUC copy is verified. The NUC must be listening on the
  service ports on its wg address (10.100.0.5), and firewall trusts wg0.
- Order for NUC wg: conduit gets the public key first, then the NUC brings up wg0 (keepalive 25 opens the path).
- the user VPN (uservpn-server, mini.themalli.ai) was retired on 2026-11-02.
- Currently-running conduit commit: unknown (no configurationRevision is set in the flake; not checked by SSH). 
- Stale comments in headscale.nix header still mention mantle; left untouched on purpose.
