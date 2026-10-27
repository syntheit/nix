#!/usr/bin/env bash
# One-time: put the Retrospend Android release key and the APNs key into secrets/harbor.yaml.
# The key, its password and the F-Droid repo password were generated outside
# git and staged in ~/.retrospend-release-keys (mode 700). This adds them to
# sops under the names hosts/harbor/secrets.nix declares, checks they decrypt,
# then shreds the staged copies. Nothing is printed and no secret is in argv.
#
#   bash hosts/harbor/retrospend-fdroid-import.sh
#
# Before it runs, back up ~/.retrospend-release-keys/retrospend.p12 somewhere
# else if you want a copy outside sops; sops (and its git history) is the
# only copy afterwards.
set -euo pipefail

keys=${KEYS_DIR:-$HOME/.retrospend-release-keys}
yaml=$(cd "$(dirname "$0")/../.." && pwd)/secrets/harbor.yaml
for f in retrospend.p12 store.pass fdroid.pass; do
	[[ -f "$keys/$f" ]] || { echo "missing $keys/$f" >&2; exit 1; }
done
# APNs auth key (Key ID S8AK338R5X, team 6NHZWHQX37) for iOS push from the dev server.
apns=${APNS_KEY:-$HOME/.secrets/retrospend-apns/AuthKey_S8AK338R5X.p8}
[[ -f "$apns" ]] || { echo "missing $apns" >&2; exit 1; }

# sops edit hands the decrypted YAML to $EDITOR as a file; this appends to it.
helper=$(mktemp)
trap 'rm -f "$helper"' EXIT
cat >"$helper" <<'EOF'
#!/usr/bin/env bash
set -eu
{
	echo "retrospend_android_keystore_b64: $(base64 -w0 "$KEYS_DIR/retrospend.p12")"
	echo "retrospend_android_keystore_password: $(tr -d '\n' <"$KEYS_DIR/store.pass")"
	echo "retrospend_fdroid_password: $(tr -d '\n' <"$KEYS_DIR/fdroid.pass")"
	echo "retrospend_apns_key_b64: $(base64 -w0 "$APNS_KEY")"
} >>"$1"
EOF
chmod 755 "$helper"

# Same key source as the `sops` alias: harbor's SSH host key, converted to age.
SOPS_AGE_KEY=$(sudo ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key)
export SOPS_AGE_KEY KEYS_DIR="$keys" APNS_KEY="$apns" EDITOR="$helper"
sudo --preserve-env=SOPS_AGE_KEY,KEYS_DIR,APNS_KEY,EDITOR sops edit "$yaml"
sudo chown "$(id -un):" "$yaml"
sudo --preserve-env=SOPS_AGE_KEY sops decrypt --extract '["retrospend_android_keystore_b64"]' "$yaml" >/dev/null
sudo --preserve-env=SOPS_AGE_KEY sops decrypt --extract '["retrospend_fdroid_password"]' "$yaml" >/dev/null
sudo --preserve-env=SOPS_AGE_KEY sops decrypt --extract '["retrospend_apns_key_b64"]' "$yaml" >/dev/null

shred -u "$keys"/retrospend.p12 "$keys"/store.pass "$keys"/fdroid.pass
rmdir "$keys"
shred -u "$apns"
rmdir "$(dirname "$apns")" 2>/dev/null || true
echo "Added to $yaml. Now run nixos-rebuild switch."
