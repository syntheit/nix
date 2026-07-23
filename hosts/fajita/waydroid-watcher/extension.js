import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const GRACE_SECONDS = 30;
const WAYDROID_PREFIX = 'waydroid.';
const WAYDROID_BIN = 'waydroid';

export default class WaydroidWatcher extends Extension {
  enable() {
    this._wins = new Set();
    this._timer = null;
    this._createdId = global.display.connect('window-created', (_d, win) => {
      GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        this._onCreated(win);
        return GLib.SOURCE_REMOVE;
      });
    });
  }

  _onCreated(win) {
    const cls = win.get_wm_class() ?? '';
    if (!cls.startsWith(WAYDROID_PREFIX))
      return;
    this._wins.add(win);
    if (this._timer) {
      GLib.source_remove(this._timer);
      this._timer = null;
    }
    const pkg = cls.slice(WAYDROID_PREFIX.length);
    win.connect('unmanaged', () => {
      this._wins.delete(win);
      this._run([WAYDROID_BIN, 'shell', '--', 'am', 'force-stop', pkg]);
      if (this._wins.size === 0) {
        this._timer = GLib.timeout_add_seconds(
          GLib.PRIORITY_DEFAULT,
          GRACE_SECONDS,
          () => {
            this._run([WAYDROID_BIN, 'session', 'stop']);
            this._timer = null;
            return GLib.SOURCE_REMOVE;
          });
      }
    });
  }

  _run(argv) {
    try {
      Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE);
    } catch (e) {
      logError(e);
    }
  }

  disable() {
    if (this._createdId)
      global.display.disconnect(this._createdId);
    if (this._timer) {
      GLib.source_remove(this._timer);
      this._timer = null;
    }
    this._wins.clear();
    this._createdId = null;
  }
}
