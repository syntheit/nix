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
#
# Startup robustness: SensorProxy / the accelerometer may not be available on
# boots where the SLPI DSP comes up frozen (a known SDM845 race). Instead of
# crashing and spamming restarts, we wait with exponential backoff (up to 5 min
# ceiling) and silently retry forever — the process stays alive and starts
# working the moment the sensor appears.
#
# Power: holding ClaimAccelerometer while the screen is off keeps the SLPI
# sensor core streaming, blocking SoC deep idle. We release the claim when the
# screen blanks (org.gnome.ScreenSaver ActiveChanged true) and re-claim +
# re-apply on unblank (ActiveChanged false).
import gi
import logging

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

logging.basicConfig(
    format="auto-rotate: %(message)s",
    level=logging.INFO,
)
log = logging.getLogger("auto-rotate")

SENSOR = "net.hadess.SensorProxy"
SENSOR_PATH = "/net/hadess/SensorProxy"
DC = "org.gnome.Mutter.DisplayConfig"
DC_PATH = "/org/gnome/Mutter/DisplayConfig"
SCREENSAVER = "org.gnome.ScreenSaver"
SCREENSAVER_PATH = "/org/gnome/ScreenSaver"

# SensorProxy orientation → mutter transform (0=normal,1=90°,2=180°,3=270°).
# Same mapping the old gsd-orientation used; flip left-up/right-up if rotation
# goes the wrong way on this device.
TRANSFORM = {"normal": 0, "left-up": 1, "bottom-up": 2, "right-up": 3}

ORIENTATION_SCHEMA = "org.gnome.settings-daemon.peripherals.touchscreen"

# Backoff schedule for sensor acquisition retries (seconds).
_BACKOFF_STEPS = [5, 10, 20, 40, 60, 120, 300]  # caps at 5 min


class AutoRotate:
    def __init__(self):
        self.system = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.last = None
        self.sensor = None          # None while unclaimed / unavailable
        self.screen_active = False  # True = screensaver active = screen off
        self._backoff_idx = 0
        self._retry_source = None   # pending GLib timeout id
        # Track whether we've already logged "no accelerometer" to avoid spam
        self._sensor_error_logged = False

        self.settings = Gio.Settings.new(ORIENTATION_SCHEMA)
        self.settings.connect("changed::orientation-lock",
                              lambda *_: self._apply_current())

        # Subscribe to screensaver ActiveChanged BEFORE claiming the sensor so
        # we don't miss a blank that happens during startup.
        self._subscribe_screensaver()

        # Re-acquire the moment SensorProxy (re)appears on the bus rather than
        # waiting out the current backoff step — iio-sensor-proxy exits on
        # zero-sensor boots and gets restarted by systemd until the SLPI
        # enumerates, which can be minutes after our own start.
        Gio.bus_watch_name(
            Gio.BusType.SYSTEM, SENSOR, Gio.BusNameWatcherFlags.NONE,
            lambda *_: self._on_sensor_appeared(),
            lambda *_: self._on_sensor_vanished())

        # Begin sensor acquisition (non-fatal if it fails).
        self._try_acquire_sensor()

    # ------------------------------------------------------------------
    # Screensaver / screen-blank handling
    # ------------------------------------------------------------------

    def _subscribe_screensaver(self):
        """Subscribe to org.gnome.ScreenSaver ActiveChanged on the session bus."""
        try:
            self.session.signal_subscribe(
                None,                   # sender (any)
                SCREENSAVER,            # interface
                "ActiveChanged",        # signal name
                SCREENSAVER_PATH,       # object path
                None,                   # arg0 filter
                Gio.DBusSignalFlags.NONE,
                self._on_screen_active_changed,
                None,
            )
        except GLib.Error as e:
            # Non-fatal: power optimisation won't work, but rotation will.
            log.warning("could not subscribe to ScreenSaver signal: %s", e.message)

    def _on_screen_active_changed(self, _conn, _sender, _path, _iface, _signal,
                                  params, _user_data):
        """Called when the screensaver activates (screen blanks) or deactivates."""
        try:
            active = params.unpack()[0]
        except Exception:
            return

        self.screen_active = active
        if active:
            # Screen going off — release the accelerometer claim to allow deep idle.
            self._release_sensor()
        else:
            # Screen coming back on — re-claim and apply any orientation change.
            self._try_acquire_sensor()

    # ------------------------------------------------------------------
    # Sensor acquisition with backoff
    # ------------------------------------------------------------------

    def _on_sensor_appeared(self):
        """SensorProxy (re)appeared on the bus — claim right away."""
        if self.sensor is not None or self.screen_active:
            return
        self._backoff_idx = 0
        self._try_acquire_sensor()

    def _on_sensor_vanished(self):
        """SensorProxy left the bus — our claim and proxy are dead."""
        self.sensor = None
        self._backoff_idx = 0
        # No retry scheduling here; _on_sensor_appeared fires when it returns.
        if self._retry_source is not None:
            GLib.source_remove(self._retry_source)
            self._retry_source = None

    def _try_acquire_sensor(self):
        """Attempt to claim the accelerometer. Schedules a retry on failure."""
        # Cancel any pending retry timer.
        if self._retry_source is not None:
            GLib.source_remove(self._retry_source)
            self._retry_source = None

        if self.sensor is not None:
            # Already claimed.
            return

        try:
            proxy = Gio.DBusProxy.new_sync(
                self.system, Gio.DBusProxyFlags.NONE, None,
                SENSOR, SENSOR_PATH, SENSOR, None)

            # Check HasAccelerometer before calling ClaimAccelerometer; on frozen
            # DSP boots SensorProxy is up but reports no sensors.
            has_accel = proxy.get_cached_property("HasAccelerometer")
            if has_accel is not None and not has_accel.unpack():
                raise RuntimeError("SensorProxy: HasAccelerometer is false")

            proxy.call_sync("ClaimAccelerometer", None,
                            Gio.DBusCallFlags.NONE, -1, None)
            proxy.connect("g-properties-changed", self._on_change)
            self.sensor = proxy
            self._backoff_idx = 0
            self._sensor_error_logged = False
            log.info("accelerometer claimed")
            self._apply_current()

        except Exception as e:
            msg = getattr(e, "message", None) or str(e)
            if not self._sensor_error_logged:
                log.warning("accelerometer not available (%s); will retry", msg)
                self._sensor_error_logged = True

            delay = _BACKOFF_STEPS[min(self._backoff_idx, len(_BACKOFF_STEPS) - 1)]
            self._backoff_idx += 1
            self._retry_source = GLib.timeout_add_seconds(delay, self._retry_cb)

    def _retry_cb(self):
        """GLib timeout callback — try to acquire sensor again."""
        self._retry_source = None
        self._try_acquire_sensor()
        return GLib.SOURCE_REMOVE

    def _release_sensor(self):
        """Release the accelerometer claim (called on screen-blank)."""
        if self.sensor is None:
            return
        # Cancel any pending retry; the screen is off, no point retrying.
        if self._retry_source is not None:
            GLib.source_remove(self._retry_source)
            self._retry_source = None
        try:
            self.sensor.call_sync("ReleaseAccelerometer", None,
                                  Gio.DBusCallFlags.NONE, -1, None)
        except GLib.Error as e:
            log.warning("ReleaseAccelerometer failed: %s", e.message)
        self.sensor = None
        log.info("accelerometer released (screen off)")

    # ------------------------------------------------------------------
    # Orientation application
    # ------------------------------------------------------------------

    def _on_change(self, _proxy, _changed, _invalidated):
        self._apply_current()

    def _apply_current(self):
        if self.settings.get_boolean("orientation-lock"):
            return
        if self.sensor is None:
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
            log.warning("apply failed: %s", e.message)

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
