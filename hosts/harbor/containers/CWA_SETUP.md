# CWA + Kobo Sync — one-time setup

Companion to `cwa.nix`. The module is fully declarative, but a few one-time
steps require pasting values into sops or editing the Kobo over USB.

## Architecture recap

```
Seafile lib "Books"
        │  (rclone move every 60s)
        ▼
/arespool/cwa-ingest    ←─── written by cwa-ingest-pull.service
        │  (CWA polling watcher: NETWORK_SHARE_MODE=true)
        ▼
/arespool/appdata/cwa/library    ←─── canonical archive
        │  (CWA Kobo Sync server impersonates Kobo's storeapi)
        ▼
Kobo Clara BW (stock Nickel)    ←─── auto-pulls books on Sync
                                     opens them in KOReader for reading
```

## 1. Seafile side

Create a dedicated library called **`Books`** in the Seafile web UI at
<https://files.matv.io>. This is the in-tray. rclone drains it on each pull.

> **Don't reuse a library you care about.** rclone uses `move`, so processed
> books are deleted from Seafile after they're copied locally. Calibre's
> library on harbor becomes the canonical archive.

## 2. Obscure the Seafile password for rclone

rclone's seafile backend stores passwords in its own obscured form (it's
deterministic obfuscation, not encryption — but it's what rclone expects).

Generate the value once on harbor (or anywhere with rclone available):

```bash
nix shell nixpkgs#rclone -c rclone obscure 'YOUR_SEAFILE_PASSWORD'
# → e.g. 8s9PHJrTjzv2g9XplC2eRBPbxFlVIMaJLEH4rq...
```

Add the **obscured** output (not the plaintext) to `secrets/harbor.yaml`:

```yaml
seafile_rclone_pass_obscured: <output of rclone obscure>
```

The `seafile_admin_email` placeholder is reused as the rclone username; if
you'd prefer a non-admin Seafile account, add a new sops key and change the
template in `secrets.nix`.

Re-encrypt: `sops secrets/harbor.yaml`.

## 3. CWA first-run

After `darwin-rebuild switch --flake .#harbor`, browse to
<https://library.matv.io>. Default login: **`admin` / `admin123`** —
**change immediately**.

Then go to **Admin → Basic Configuration → Feature Configuration** and:

- ✅ Enable **Kobo Sync**
- ✅ Enable **KOReader Sync**
- ❌ Turn **OFF** "Embed Metadata to Ebook File on Download/Conversion"
  (it corrupts EPUBs in ways Kobo can't parse)

Drop a test EPUB into the Seafile `Books` library and wait ~90s. It
should appear in the CWA library with full metadata.

## 4. Kobo Sync — get a sync URL

In CWA, **User profile → OAuth & API Integrations → Kobo Sync Token →
Create**. Copy the URL it gives you — format:

```
api_endpoint=https://library.matv.io/kobo/<token>
```

## 5. Kobo Sync — point the device at CWA

The Kobo's stock sync uses the URL in `[OneStoreServices]` of
`.kobo/Kobo/Kobo eReader.conf` on the device. **Edit it once over USB.**

> ⚠️ **Use mtools, not Finder/cp.** macOS's FAT32 driver writes long-filename
> entries the Kobo's `fsck.vfat` corrupts on next boot. See
> `~/.claude/projects/-Users-daniel/memory/feedback_kobo_fat32_macos.md`.

Plug the Kobo in and tap "Connect" on the device:

```bash
diskutil unmount /Volumes/KOBOeReader
MCOPY=$(nix shell nixpkgs#mtools -c which mcopy)
MTYPE=$(nix shell nixpkgs#mtools -c which mtype)
MDEL=$(nix shell nixpkgs#mtools -c which mdel)

# Pull the conf, edit the api_endpoint line, push it back
sudo "$MTYPE" -i /dev/disk4 '::/.kobo/Kobo/Kobo eReader.conf' > /tmp/kobo.conf
sed -i.bak 's|^api_endpoint=.*|api_endpoint=https://library.matv.io/kobo/<TOKEN>|' /tmp/kobo.conf
sudo "$MDEL" -i /dev/disk4 '::/.kobo/Kobo/Kobo eReader.conf'
sudo "$MCOPY" -i /dev/disk4 -m /tmp/kobo.conf '::/.kobo/Kobo/Kobo eReader.conf'

diskutil eject /dev/disk4
```

Replace `disk4` with whatever `diskutil list` shows for `KOBOeReader`.

Unplug, then on the Kobo tap **Sync** in the bottom-right menu. Books from
the CWA library will appear under "My Books" with covers — same UX as the
Kobo store, but pointing at your library.

## 6. KOReader reading-progress sync (optional)

CWA also bundles a kosync-compatible endpoint at `https://library.matv.io`.
In KOReader: **Cloud storage → Progress sync → server `https://library.matv.io`**
(no `/kosync` suffix — that 401s, see CWA issue #457). Use your CWA login.

## 7. After firmware updates

Kobo firmware updates can revert `Kobo eReader.conf`. After any FW bump,
re-do step 5. (Clara BW historically does NOT revert this file, but check.)
