#!/usr/bin/env python3
# Phone Check — a tiny libadwaita diagnostic panel for fajita.
# - Live sensor readouts (accelerometer / light / proximity) so hardware can
#   be eyeballed without a terminal.
# - Keyring status + a "Re-key to no password" action that changes the login
#   keyring's master password to empty so GDM autologin can auto-unlock it.
#   The current password is typed into a local GTK entry and passed straight
#   to gnome-keyring over D-Bus; it never leaves the device.
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gio, GLib

SECRETS = "org.freedesktop.secrets"
SECRETS_PATH = "/org/freedesktop/secrets"
LOGIN = "/org/freedesktop/secrets/collection/login"
COLL_IFACE = "org.freedesktop.Secret.Collection"
GUILT = "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface"
SENSOR = "net.hadess.SensorProxy"
SENSOR_PATH = "/net/hadess/SensorProxy"


class PhoneCheck(Adw.Application):
    def __init__(self):
        super().__init__(application_id="io.matv.PhoneCheck")
        self.bus = None
        self.sensor = None

    def do_activate(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

        win = Adw.ApplicationWindow(application=self, title="Phone Check")
        win.set_default_size(420, 720)

        page = Adw.PreferencesPage()
        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(Adw.HeaderBar())
        toolbar.set_content(page)
        win.set_content(toolbar)

        # --- Sensors ---
        sg = Adw.PreferencesGroup(title="Sensors", description="Tilt / cover the top of the phone")
        self.accel_row = Adw.ActionRow(title="Accelerometer", subtitle="…")
        self.light_row = Adw.ActionRow(title="Ambient light", subtitle="…")
        self.prox_row = Adw.ActionRow(title="Proximity", subtitle="…")
        for r in (self.accel_row, self.light_row, self.prox_row):
            sg.add(r)
        page.add(sg)

        # --- Keyring ---
        kg = Adw.PreferencesGroup(title="Keyring")
        self.kr_row = Adw.ActionRow(title="Login keyring", subtitle="…")
        kg.add(self.kr_row)
        rekey = Adw.ButtonRow(title="Re-key to no password")
        rekey.connect("activated", self.on_rekey_clicked)
        kg.add(rekey)
        page.add(kg)
        self.refresh_keyring()

        # Live sensors
        try:
            self.sensor = Gio.DBusProxy.new_sync(
                self.bus, Gio.DBusProxyFlags.NONE, None,
                SENSOR, SENSOR_PATH, SENSOR, None)
            for m in ("ClaimAccelerometer", "ClaimLight", "ClaimProximity"):
                try:
                    self.sensor.call_sync(m, None, Gio.DBusCallFlags.NONE, -1, None)
                except GLib.Error:
                    pass
            self.sensor.connect("g-properties-changed", lambda *a: self.refresh_sensors())
        except GLib.Error as e:
            self.accel_row.set_subtitle(f"SensorProxy unavailable: {e.message}")
        self.refresh_sensors()

        win.connect("close-request", self.on_close)
        win.present()

    def _prop(self, name, default=None):
        v = self.sensor.get_cached_property(name) if self.sensor else None
        return v.unpack() if v is not None else default

    def refresh_sensors(self):
        if not self.sensor:
            return
        has_a = self._prop("HasAccelerometer", False)
        self.accel_row.set_subtitle(
            f"orientation: {self._prop('AccelerometerOrientation', 'undefined')}"
            if has_a else "not present")
        has_l = self._prop("HasAmbientLight", False)
        if has_l:
            unit = self._prop("LightLevelUnit", "")
            self.light_row.set_subtitle(f"{self._prop('LightLevel', 0):.1f} {unit}")
        else:
            self.light_row.set_subtitle("not present")
        has_p = self._prop("HasProximity", False)
        self.prox_row.set_subtitle(
            ("near" if self._prop("ProximityNear", False) else "far")
            if has_p else "not present")

    def refresh_keyring(self):
        try:
            coll = Gio.DBusProxy.new_sync(
                self.bus, Gio.DBusProxyFlags.NONE, None,
                SECRETS, LOGIN, COLL_IFACE, None)
            locked = coll.get_cached_property("Locked")
            items = coll.get_cached_property("Items")
            n = len(items.unpack()) if items else 0
            state = "LOCKED" if (locked and locked.unpack()) else "unlocked"
            self.kr_row.set_subtitle(f"{state} · {n} secrets stored")
        except GLib.Error as e:
            self.kr_row.set_subtitle(f"error: {e.message}")

    def on_rekey_clicked(self, _row):
        dialog = Adw.AlertDialog(
            heading="Re-key login keyring",
            body="Type your current login password. It is sent only to the "
                 "on-device keyring daemon to change the keyring's password to "
                 "empty, so it unlocks automatically at boot. Nothing is stored "
                 "or sent anywhere.")
        entry = Gtk.PasswordEntry(show_peek_icon=True, margin_top=8,
                                  margin_start=12, margin_end=12)
        dialog.set_extra_child(entry)
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("ok", "Re-key")
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("ok")
        dialog.connect("response", self.on_rekey_response, entry)
        dialog.present(self.get_active_window())

    def on_rekey_response(self, dialog, response, entry):
        if response != "ok":
            return
        old = entry.get_text()
        try:
            out = self.bus.call_sync(
                SECRETS, SECRETS_PATH, "org.freedesktop.Secret.Service",
                "OpenSession", GLib.Variant("(sv)", ("plain", GLib.Variant("s", ""))),
                None, Gio.DBusCallFlags.NONE, -1, None)
            _out, session = out.unpack()
            original = (session, b"", old.encode("utf-8"), "text/plain")
            master = (session, b"", b"", "text/plain")
            self.bus.call_sync(
                SECRETS, SECRETS_PATH, GUILT, "ChangeWithMasterPassword",
                GLib.Variant("(o(oayays)(oayays))", (LOGIN, original, master)),
                None, Gio.DBusCallFlags.NONE, -1, None)
            self.toast("Re-keyed. It should now auto-unlock after a reboot.")
            self.refresh_keyring()
        except GLib.Error as e:
            self.toast(f"Failed: {e.message}")

    def toast(self, text):
        d = Adw.AlertDialog(heading="Phone Check", body=text)
        d.add_response("ok", "OK")
        d.present(self.get_active_window())

    def on_close(self, _win):
        if self.sensor:
            for m in ("ReleaseAccelerometer", "ReleaseLight", "ReleaseProximity"):
                try:
                    self.sensor.call_sync(m, None, Gio.DBusCallFlags.NONE, -1, None)
                except GLib.Error:
                    pass
        return False


if __name__ == "__main__":
    import sys
    PhoneCheck().run(sys.argv)
