#!/system/bin/sh
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
sleep 15
magisk resetprop ro.debuggable 1
settings put system screen_brightness 0
settings put system screen_brightness_mode 0
sleep 5
svc power stayon usb
input keyevent KEYCODE_WAKEUP
input keyevent KEYCODE_MENU
sleep 3
# Start Termux sshd first (before VM takes foreground)
am start -W -n com.termux/.HomeActivity
sleep 5
su 10228 -c 'export PREFIX=/data/data/com.termux/files/usr HOME=/data/data/com.termux/files/home LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib; /data/data/com.termux/files/usr/bin/sshd'
# Launch VM terminal last so it stays in foreground
am start -S -W -n com.android.virtualization.terminal/.MainActivity
sleep 30
svc power stayon false
settings put system screen_off_timeout 1000

# Watchdog — restart VM if it dies
while true; do
    sleep 30
    if ! ip neigh | grep -q avf_tap; then
        input keyevent KEYCODE_WAKEUP
        sleep 2
        svc power stayon usb
        am start -S -W -n com.android.virtualization.terminal/.MainActivity
        sleep 30
        svc power stayon false
    fi
done