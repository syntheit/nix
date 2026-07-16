#!/usr/bin/env python3
# Minimal auto-rotate daemon for fajita.
#
# GNOME 49 dropped gsd's orientation plugin, and mutter doesn't mark this DSI
# panel `panel-orientation-managed`, so nothing turns accelerometer orientation
# into a screen rotation. The sensor stack works (net.hadess.SensorProxy on the
# system bus reports AccelerometerOrientation); this daemon claims it and
# applies the matching monitor transform via org.gnome.Mutter.DisplayConfig —
# the exact call our manual quick-settings toggle already uses successfully.
#
# Runs as a systemd --user service inside the graphical session (so the accel
# claim is authorized and DisplayConfig is reachable).
import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

SENSOR = "net.hadess.SensorProxy"
SENSOR_PATH = "/net/hadess/SensorProxy"
DC = "org.gnome.Mutter.DisplayConfig"
DC_PATH = "/org/gnome/Mutter/DisplayConfig"

# SensorProxy orientation → mutter transform (0=normal,1=90°,2=180°,3=270°).
# Same mapping the old gsd-orientation used; flip left-up/right-up if rotation
# goes the wrong way on this device.
TRANSFORM = {"normal": 0, "left-up": 1, "bottom-up": 2, "right-up": 3}


ORIENTATION_SCHEMA = "org.gnome.settings-daemon.peripherals.touchscreen"


class AutoRotate:
    def __init__(self):
        self.system = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.last = None

        # The quick-settings "Auto Rotate" toggle writes orientation-lock (the
        # standard gsetting, shipped by verdre's gsd-mobile). When locked, hold
        # the current orientation.
        self.settings = Gio.Settings.new(ORIENTATION_SCHEMA)
        self.settings.connect("changed::orientation-lock",
                              lambda *_: self._apply_current())

        self.sensor = Gio.DBusProxy.new_sync(
            self.system, Gio.DBusProxyFlags.NONE, None,
            SENSOR, SENSOR_PATH, SENSOR, None)
        self.sensor.call_sync("ClaimAccelerometer", None,
                              Gio.DBusCallFlags.NONE, -1, None)
        self.sensor.connect("g-properties-changed", self._on_change)
        self._apply_current()

    def _on_change(self, _proxy, _changed, _invalidated):
        self._apply_current()

    def _apply_current(self):
        if self.settings.get_boolean("orientation-lock"):
            return
        v = self.sensor.get_cached_property("AccelerometerOrientation")
        if v is None:
            return
        orient = v.unpack()
        transform = TRANSFORM.get(orient)
        if transform is None or orient == self.last:
            return
        try:
            self._apply(transform)
            self.last = orient
        except GLib.Error as e:
            print(f"auto-rotate: apply failed: {e.message}", flush=True)

    def _apply(self, transform):
        reply = self.session.call_sync(
            DC, DC_PATH, DC, "GetCurrentState", None, None,
            Gio.DBusCallFlags.NONE, -1, None)
        serial, monitors, logicals, _props = reply.unpack()

        new_logicals = []
        for x, y, scale, _t, primary, assigned, _lprops in logicals:
            phys = []
            for connector, *_ in assigned:
                mon = next(m for m in monitors if m[0][0] == connector)
                mode_id = next(md[0] for md in mon[1] if md[6].get("is-current"))
                phys.append((connector, mode_id, {}))
            new_logicals.append((x, y, scale, transform, primary, phys))

        # method 1 = temporary (reverts to portrait on next login/reboot)
        self.session.call_sync(
            DC, DC_PATH, DC, "ApplyMonitorsConfig",
            GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})",
                         (serial, 1, new_logicals, {})),
            None, Gio.DBusCallFlags.NONE, -1, None)


if __name__ == "__main__":
    AutoRotate()
    GLib.MainLoop().run()
