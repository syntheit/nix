#!/system/bin/sh
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
sleep 15
magisk resetprop ro.debuggable 1

# Guard the NixOS image against the Terminal app replacing it. Every path that
# deletes it (Recovery "Reset", the upgrade flow, the installer) unlinks or
# renames entries in files/linux; an immutable directory makes those fail with
# EPERM, even for root or "Clear storage", while root_part/efi_part stay
# writable. The small metadata files are never written outside those paths.
# Disabling the components also keeps their screens from ever coming up under
# the blind tap below. Undo all of this (chattr -i, pm enable) before moving
# the VM to a new Terminal version — the Android 17 one replaces nixos-avf
# images (nix-community/nixos-avf#42), so major LineageOS upgrades stay blocked.
TERMINAL=com.android.virtualization.terminal
IMAGE_DIR=/data/data/$TERMINAL/files/linux
chattr +i "$IMAGE_DIR/completed" "$IMAGE_DIR/build_id" "$IMAGE_DIR/vm_config.json" "$IMAGE_DIR"
# pm disable kills the app, so this must stay ahead of the Terminal launch.
for c in UpgradeActivity SettingsRecoveryActivity SettingsDiskResizeActivity InstallerActivity InstallerService; do
    pm disable "$TERMINAL/.$c" >/dev/null
done
magisk resetprop lineage.updater.allow_major_upgrades false
# crosvm is a "phantom process" of the Terminal app; don't let Android police it.
settings put global settings_enable_monitor_phantom_procs false
# Keep screen alive throughout boot — previous boot left timeout at 1s
settings put system screen_off_timeout 120000
settings put system screen_brightness 0
settings put system screen_brightness_mode 0
sleep 5
svc power stayon true
input keyevent KEYCODE_WAKEUP
input keyevent KEYCODE_MENU
sleep 3
# Start Termux sshd first (before VM takes foreground)
am start -W -n com.termux/.HomeActivity
sleep 5
su 10228 -c 'export PREFIX=/data/data/com.termux/files/usr HOME=/data/data/com.termux/files/home LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib; /data/data/com.termux/files/usr/bin/sshd'
# Every VM start, the Terminal sizes root_part to 95% of /data while the
# read-only terminal_storage_balloon flag is on; with it off it would run
# resize2fs -M on the image instead. If an OS update ever flips it, stay down
# (Termux sshd is already up) rather than let the app shrink the filesystem.
if aflags list 2>/dev/null | grep 'flags\.terminal_storage_balloon ' | grep -q ' disabled '; then
    log -t start-vm "terminal_storage_balloon is disabled; not starting the VM"
    exit 1
fi
# Launch VM terminal last so it stays in foreground
am start -S -W -n com.android.virtualization.terminal/.MainActivity
sleep 45
input keyevent KEYCODE_WAKEUP
sleep 2
input tap 720 1560
sleep 30
# Power down screen
svc power stayon false
settings put system screen_off_timeout 1000

# Watchdog — restart VM if it dies
while true; do
    sleep 30
    # The neighbour entry can linger as INCOMPLETE after the VM dies, which
    # still matches; the crosvm process is the direct signal.
    if ! pidof crosvm_debian >/dev/null || ! ip neigh | grep -q avf_tap; then
        settings put system screen_off_timeout 120000
        svc power stayon true
        input keyevent KEYCODE_WAKEUP
        sleep 2
        am start -S -W -n com.android.virtualization.terminal/.MainActivity
        sleep 45
        input keyevent KEYCODE_WAKEUP
        sleep 2
        input tap 720 1560
        sleep 30
        svc power stayon false
        settings put system screen_off_timeout 1000
    fi
done
