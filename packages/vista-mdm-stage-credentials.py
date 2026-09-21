"""Stage one API key and one distinct HMAC key for NanoMDM and Deus.

Executed only by the default-off Vista Nix cutover. No key bytes are logged or
passed in argv. Both consumers receive identical exact bytes: source secrets
with a trailing newline are rejected, not silently normalized.
"""

import os
import stat
import sys
import tempfile
from pathlib import Path


DEUS_UID = 3999


def read_key(path: Path, *, min_length: int, max_length: int) -> bytes:
    value = path.read_bytes()
    if not min_length <= len(value) <= max_length or any(not 33 <= b <= 126 for b in value):
        raise ValueError("credential has invalid length or non-printable bytes")
    return value


def private_directory(path: Path, uid: int) -> None:
    try:
        path.mkdir(mode=0o700)
        os.chown(path, uid, uid)
    except FileExistsError:
        pass
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o700 or info.st_uid != uid or info.st_gid != uid:
        raise ValueError("credential directory owner or mode is unsafe")


def root_parent(path: Path) -> None:
    try:
        path.mkdir(mode=0o755)
    except FileExistsError:
        pass
    info = path.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_gid != 0
            or info.st_mode & 0o022):
        raise ValueError("credential parent is not a root-owned directory")


def atomic_private_file(directory: Path, name: str, value: bytes, uid: int) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{name}.", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        os.fchown(fd, uid, uid)
        with os.fdopen(fd, "wb") as destination:
            destination.write(value)
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary, directory / name)
    except BaseException:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def stage(api_source: Path, hmac_source: Path, nanodep_source: Path,
          nano_dir: Path, deus_dir: Path, legacy_api: Path,
          ddm_send_source: Path = None, ddm_recv_source: Path = None,
          ddm_receipt_source: Path = None) -> None:
    api = read_key(api_source, min_length=1, max_length=4096)
    hmac = read_key(hmac_source, min_length=32, max_length=256)
    nanodep = read_key(nanodep_source, min_length=1, max_length=4096)
    # The declarative-management keys are optional and all-or-nothing: NanoMDM
    # signs DM requests with the send key and verifies Deus's responses with
    # the receive key, so a half-configured pair is a silent one-way trust.
    # The receipt key is Deus's third key, which it demands whenever DDM is on
    # — a missing one disables its whole private listener, not just receipts —
    # so it is part of the same all-or-nothing set rather than an extra.
    ddm_sources = (ddm_send_source, ddm_recv_source, ddm_receipt_source)
    if any(source is None for source in ddm_sources) and any(
            source is not None for source in ddm_sources):
        raise ValueError("declarative management needs all three DM HMAC sources")
    declarative = {}
    if ddm_send_source is not None:
        declarative["ddm-send-hmac"] = read_key(ddm_send_source, min_length=32, max_length=256)
        declarative["ddm-recv-hmac"] = read_key(ddm_recv_source, min_length=32, max_length=256)
        declarative["ddm-receipt-hmac"] = read_key(
            ddm_receipt_source, min_length=32, max_length=256)
    values = [api, hmac, nanodep, *declarative.values()]
    if len(set(values)) != len(values):
        raise ValueError("NanoMDM, NanoDEP, webhook, and DM credentials must be distinct")
    root_parent(nano_dir.parent)
    root_parent(deus_dir.parent)
    root_parent(legacy_api.parent)
    private_directory(nano_dir, 0)
    private_directory(deus_dir, DEUS_UID)
    for directory, uid in ((nano_dir, 0), (deus_dir, DEUS_UID)):
        atomic_private_file(directory, "nanomdm-api", api, uid)
        atomic_private_file(directory, "webhook-hmac", hmac, uid)
        for name, value in declarative.items():
            atomic_private_file(directory, name, value, uid)
    # Preserve rollback bytes without leaving the old 0444 leak behind. The
    # default-off deus-stage path is skipped in this mode, so it cannot undo
    # the private replacement later in activation ordering.
    atomic_private_file(legacy_api.parent, legacy_api.name, api, DEUS_UID)


if __name__ == "__main__":
    if len(sys.argv) not in (7, 10):
        raise SystemExit("usage: stage API_SOURCE HMAC_SOURCE NANODEP_SOURCE NANO_DIR "
                         "DEUS_DIR LEGACY_API "
                         "[DM_SEND_SOURCE DM_RECV_SOURCE DM_RECEIPT_SOURCE]")
    try:
        stage(*(Path(argument) for argument in sys.argv[1:]))
    except (OSError, ValueError) as error:
        # Never include file contents in activation logs.
        raise SystemExit(f"MDM credential staging failed: {error}") from None
