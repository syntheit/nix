#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANDROID_GW=$(ip route | grep default | awk '{print $3}')
SSH="ssh -p 8022 -i ~/.ssh/mainkey -o BatchMode=yes -o StrictHostKeyChecking=no $ANDROID_GW"

LOCAL_HASH=$(sha256sum "$SCRIPT_DIR/start-vm.sh" | awk '{print $1}')

echo "Deploying start-vm.sh to Android ($ANDROID_GW)..."
scp -P 8022 -i ~/.ssh/mainkey -o StrictHostKeyChecking=no "$SCRIPT_DIR/start-vm.sh" "$ANDROID_GW:/data/local/tmp/"
$SSH "su -c 'cp /data/local/tmp/start-vm.sh /data/adb/service.d/start-vm.sh && chmod 755 /data/adb/service.d/start-vm.sh'"

REMOTE_HASH=$($SSH "su -c 'sha256sum /data/adb/service.d/start-vm.sh'" | awk '{print $1}')

if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
    echo "Verified: hashes match ($LOCAL_HASH)"
    echo "Reboot Android to apply."
else
    echo "ERROR: hash mismatch!"
    echo "  Local:  $LOCAL_HASH"
    echo "  Remote: $REMOTE_HASH"
    exit 1
fi