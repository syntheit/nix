#!/system/bin/sh
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
sleep 15
magisk resetprop ro.debuggable 1
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
    if ! ip neigh | grep -q avf_tap; then
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
