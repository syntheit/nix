# Caspian Crash Course

## Modifier Key
- **`$mod`** = `SUPER` (Windows key / Command key)

---

## 🚀 Application Launchers & Windows

| Keybinding | Action |
|------------|--------|
| `SUPER + Enter` | Open **Rofi** application launcher |
| `SUPER + Shift + Enter` | Open **Kitty** terminal |
| `SUPER + B` | Open **zen** browser |
| `SUPER + E` | Open **Nemo** file manager |
| `SUPER + C` | Open **Cava** (audio visualizer) in Kitty |

---

## 🪟 Window Management

| Keybinding | Action |
|------------|--------|
| `SUPER + Space` | Toggle window **floating** mode |
| `SUPER + F` | Toggle **fullscreen** |
| `SUPER + Q` | **Kill** (close) active window |

---

## 🧭 Window Navigation (Vim-style)

| Keybinding | Action |
|------------|--------|
| `SUPER + H` | Move focus **left** |
| `SUPER + L` | Move focus **right** |
| `SUPER + J` | Move focus **down** |
| `SUPER + K` | Move focus **up** |

*Note: These follow Vim's HJKL movement pattern*

---

## 🖥️ Workspaces

| Keybinding | Action |
|------------|--------|
| `SUPER + 1-9, 0` | **Switch to** workspace 1-10 |
| `SUPER + Shift + 1-9, 0` | **Move window to** workspace 1-10 |
| `SUPER + .` | **Switch to** next workspace |
| `SUPER + ,` | **Switch to** previous workspace |
| `SUPER + Shift + .` | **Move window to** next workspace |
| `SUPER + Shift + ,` | **Move window to** previous workspace |

*Workspaces 1-10 are available. The "0" key maps to workspace 10.*

---

## 🖱️ Mouse Controls

| Keybinding | Action |
|------------|--------|
| `SUPER + Left Mouse Button` | **Drag** window (move) |
| `SUPER + Right Mouse Button` | **Resize** window |
| `SUPER + Middle Mouse Button` | Toggle window **floating** |

---

## 🔊 Audio Controls

| Keybinding | Action |
|------------|--------|
| `XF86AudioMute` | Toggle **mute** |
| `XF86AudioRaiseVolume` | **Increase** volume (+5%) |
| `XF86AudioLowerVolume` | **Decrease** volume (-5%) |
| `XF86AudioPlay` | **Play/Pause** media |
| `XF86AudioNext` | **Next** track |
| `XF86AudioPrev` | **Previous** track |

*These are typically your function keys (F1-F12) or dedicated media keys. Volume changes in 5% increments.*

## 🎵 Waybar Media Player (MPRIS)

The media player module in Waybar (displayed on the left, next to workspaces) shows the current track and provides mouse controls:

| Action | Function |
|-------|----------|
| **Left Click** | **Switch to** workspace where Spotify/media player is running |
| **Right Click** | **Next** track |
| **Middle Click** | **Previous** track |

*The media player displays "Song Name - Artist" and appears as a pill-shaped widget when media is playing. Clicking it switches to the workspace containing the media player application.*

---

## 📸 Screenshots

| Keybinding | Action |
|------------|--------|
| `SUPER + Shift + S` | Screenshot **selected area** (freeze, copy to clipboard) |
| `SUPER + Shift + A` | Screenshot **entire screen** (copy to clipboard) |
| `SUPER + W` | Screenshot **active window** (copy to clipboard) |
| `SUPER + Shift + W` | Screenshot **active window** (save to file) |
| `SUPER + O` | Screenshot **current monitor/output** (copy to clipboard) |
| `SUPER + Shift + O` | Screenshot **current monitor/output** (save to file) |

*All screenshots use grimblast. The "freeze" option on area selection pauses the screen for easier selection.*

---

## 📋 Clipboard Manager

| Keybinding | Action |
|------------|--------|
| `SUPER + V` | Toggle **CopyQ** clipboard manager |
| `SUPER + Shift + V` | Open **CopyQ** menu |

---

## 🔒 Lock Screen

| Keybinding | Action |
|------------|--------|
| `SUPER + Shift + L` | **Lock** screen (hyprlock) |

---

## ⌨️ Typing Accents (Compose Key)

The **Right Alt** key is configured as the **Compose key** for typing accented characters.

### How to Use
1. Press and release **Right Alt** (the compose key)
2. Type the accent mark
3. Type the letter

### Spanish Accents

| Sequence | Result | Example |
|----------|--------|---------|
| `Right Alt` + `'` + `a` | **á** | **café** |
| `Right Alt` + `'` + `e` | **é** | **café** |
| `Right Alt` + `'` + `i` | **í** | **país** |
| `Right Alt` + `'` + `o` | **ó** | **corazón** |
| `Right Alt` + `'` + `u` | **ú** | **tú** |
| `Right Alt` + `~` + `n` | **ñ** | **español** |
| `Right Alt` + `?` + `?` | **¿** | **¿Cómo?** |
| `Right Alt` + `!` + `!` | **¡** | **¡Hola!** |

### French Accents

| Sequence | Result | Example |
|----------|--------|---------|
| `Right Alt` + `` ` `` + `a` | **à** | **à** |
| `Right Alt` + `` ` `` + `e` | **è** | **très** |
| `Right Alt` + `` ` `` + `u` | **ù** | **où** |
| `Right Alt` + `'` + `e` | **é** | **café** |
| `Right Alt` + `^` + `a` | **â** | **château** |
| `Right Alt` + `^` + `e` | **ê** | **fête** |
| `Right Alt` + `^` + `i` | **î** | **île** |
| `Right Alt` + `^` + `o` | **ô** | **hôtel** |
| `Right Alt` + `^` + `u` | **û** | **sûr** |
| `Right Alt` + `"` + `a` | **ä** | **Noël** |
| `Right Alt` + `"` + `e` | **ë** | **Noël** |
| `Right Alt` + `"` + `i` | **ï** | **naïf** |
| `Right Alt` + `"` + `o` | **ö** | **cœur** |
| `Right Alt` + `"` + `u` | **ü** | **aiguë** |
| `Right Alt` + `,` + `c` | **ç** | **français** |

### Portuguese Accents

| Sequence | Result | Example |
|----------|--------|---------|
| `Right Alt` + `'` + `a` | **á** | **café** |
| `Right Alt` + `` ` `` + `a` | **à** | **à** |
| `Right Alt` + `^` + `a` | **â** | **português** |
| `Right Alt` + `~` + `a` | **ã** | **português** |
| `Right Alt` + `'` + `e` | **é** | **café** |
| `Right Alt` + `^` + `e` | **ê** | **português** |
| `Right Alt` + `'` + `i` | **í** | **país** |
| `Right Alt` + `^` + `i` | **î** | **português** |
| `Right Alt` + `'` + `o` | **ó** | **corazão** |
| `Right Alt` + `^` + `o` | **ô** | **português** |
| `Right Alt` + `~` + `o` | **õ** | **português** |
| `Right Alt` + `'` + `u` | **ú** | **tú** |
| `Right Alt` + `^` + `u` | **û** | **português** |
| `Right Alt` + `~` + `n` | **ñ** | **español** |

### Quick Reference
- **Acute accent (á, é, í, ó, ú)**: `Right Alt` + `'` + letter
- **Grave accent (à, è, ù)**: `Right Alt` + `` ` `` + letter
- **Circumflex (â, ê, î, ô, û)**: `Right Alt` + `^` + letter
- **Tilde (ã, õ, ñ)**: `Right Alt` + `~` + letter
- **Diaeresis/umlaut (ä, ë, ï, ö, ü)**: `Right Alt` + `"` + letter
- **Cedilla (ç)**: `Right Alt` + `,` + `c`

*Note: The compose key sequences work in most applications. Some applications may have their own input methods.*

---

## 💡 Tips & Tricks

1. **Window Movement**: Hold `SUPER` and drag with left mouse button to move windows
2. **Window Resizing**: Hold `SUPER` and drag with right mouse button to resize windows
3. **Floating Windows**: Use `SUPER + Space` to toggle floating mode for any window
4. **Workspace Organization**: Use workspaces to organize your workflow (e.g., workspace 1 for terminal, workspace 2 for browser)
5. **Quick App Launch**: `SUPER + Enter` opens Rofi, which can launch any installed application
6. **Clipboard History**: Use `SUPER + V` to access your clipboard history with CopyQ

---

## 🎯 Common Workflows

**Opening a terminal:**
- `SUPER + Shift + Enter` (direct) or `SUPER + Enter` then type "kitty"

**Opening a file manager:**
- `SUPER + E` opens Nemo

**Moving a window to another workspace:**
- `SUPER + Shift + [1-9,0]` (to specific workspace)
- `SUPER + Shift + .` (to next workspace)
- `SUPER + Shift + ,` (to previous workspace)

**Taking a screenshot:**
- `SUPER + Shift + S` for area selection (freezes screen)
- `SUPER + Shift + A` for full screen with cursor
- `SUPER + W` for active window
- `SUPER + O` for current monitor

**Managing audio:**
- Use your media keys or function keys for volume/playback control
- Volume adjusts in 5% increments

**Accessing clipboard history:**
- `SUPER + V` to toggle CopyQ, `SUPER + Shift + V` for menu

**Locking your screen:**
- `SUPER + Shift + L`
