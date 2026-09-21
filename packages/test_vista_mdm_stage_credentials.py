"""Offline checks for the default-off Vista MDM credential staging helper."""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("vista-mdm-stage-credentials.py")
SPEC = importlib.util.spec_from_file_location("vista_mdm_stage_credentials", MODULE_PATH)
stage_credentials = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(stage_credentials)


class StageCredentialsTests(unittest.TestCase):
    def test_key_bytes_are_exact_and_newline_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "key"
            source.write_bytes(b"a" * 32)
            self.assertEqual(stage_credentials.read_key(source, min_length=32, max_length=256), b"a" * 32)
            source.write_bytes(b"a" * 32 + b"\n")
            with self.assertRaises(ValueError):
                stage_credentials.read_key(source, min_length=32, max_length=256)

    def test_invalid_or_reused_keys_write_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            api, hmac, nanodep = (base / name for name in ("api", "hmac", "nanodep"))
            api.write_bytes(b"a" * 32)
            hmac.write_bytes(b"a" * 32)
            nanodep.write_bytes(b"c" * 32)
            with mock.patch.object(stage_credentials, "private_directory") as directory:
                with mock.patch.object(stage_credentials, "atomic_private_file") as write:
                    with self.assertRaises(ValueError):
                        stage_credentials.stage(api, hmac, nanodep, base / "nano", base / "deus", base / "legacy")
                    directory.assert_not_called()
                    write.assert_not_called()

    def test_valid_keys_are_staged_to_both_consumers_and_resecure_legacy_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            api, hmac, nanodep = (base / name for name in ("api", "hmac", "nanodep"))
            api.write_bytes(b"a" * 32)
            hmac.write_bytes(b"b" * 32)
            nanodep.write_bytes(b"c" * 32)
            with mock.patch.object(stage_credentials, "root_parent"):
                with mock.patch.object(stage_credentials, "private_directory"):
                    with mock.patch.object(stage_credentials, "atomic_private_file") as write:
                        stage_credentials.stage(api, hmac, nanodep,
                                                base / "nano", base / "deus", base / "legacy")
            self.assertEqual(write.call_count, 5)
            self.assertEqual(write.call_args.args, (base, "legacy", b"a" * 32,
                                                    stage_credentials.DEUS_UID))

    def test_successful_stage_writes_exact_private_files_and_replaces_old_copy(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            nano, deus = base / "nano", base / "deus"
            nano.mkdir(mode=0o700)
            deus.mkdir(mode=0o700)
            api, hmac, nanodep = (base / name for name in ("api", "hmac", "nanodep"))
            api.write_bytes(b"a" * 32)
            hmac.write_bytes(b"b" * 32)
            nanodep.write_bytes(b"c" * 32)
            legacy = base / "legacy"
            legacy.write_bytes(b"old-exposed-key")
            legacy.chmod(0o444)
            # Only the ownership operations are mocked; the temp-dir writes,
            # atomic replacement, bytes and modes are all real.
            with mock.patch.object(stage_credentials, "root_parent"):
                with mock.patch.object(stage_credentials, "private_directory"):
                    with mock.patch.object(stage_credentials.os, "fchown"):
                        stage_credentials.stage(api, hmac, nanodep, nano, deus, legacy)
            for directory in (nano, deus):
                self.assertEqual((directory / "nanomdm-api").read_bytes(), b"a" * 32)
                self.assertEqual((directory / "webhook-hmac").read_bytes(), b"b" * 32)
                self.assertEqual((directory / "nanomdm-api").stat().st_mode & 0o777, 0o600)
                self.assertEqual((directory / "webhook-hmac").stat().st_mode & 0o777, 0o600)
            self.assertEqual(legacy.read_bytes(), b"a" * 32)
            self.assertEqual(legacy.stat().st_mode & 0o777, 0o600)

    def test_declarative_management_pair_is_all_or_nothing_and_distinct(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            api, hmac, nanodep, send, recv = (
                base / name for name in ("api", "hmac", "nanodep", "send", "recv"))
            api.write_bytes(b"a" * 32)
            hmac.write_bytes(b"b" * 32)
            nanodep.write_bytes(b"c" * 32)
            send.write_bytes(b"d" * 32)
            recv.write_bytes(b"e" * 32)
            with mock.patch.object(stage_credentials, "root_parent"):
                with mock.patch.object(stage_credentials, "private_directory"):
                    with mock.patch.object(stage_credentials, "atomic_private_file") as write:
                        with self.assertRaises(ValueError):
                            stage_credentials.stage(api, hmac, nanodep, base / "nano",
                                                    base / "deus", base / "legacy", send)
                        recv.write_bytes(b"d" * 32)
                        with self.assertRaises(ValueError):
                            stage_credentials.stage(api, hmac, nanodep, base / "nano",
                                                    base / "deus", base / "legacy", send, recv)
                        recv.write_bytes(b"e" * 31)
                        with self.assertRaises(ValueError):
                            stage_credentials.stage(api, hmac, nanodep, base / "nano",
                                                    base / "deus", base / "legacy", send, recv)
                        write.assert_not_called()

    def test_declarative_management_keys_reach_both_consumers(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            nano, deus = base / "nano", base / "deus"
            nano.mkdir(mode=0o700)
            deus.mkdir(mode=0o700)
            api, hmac, nanodep, send, recv = (
                base / name for name in ("api", "hmac", "nanodep", "send", "recv"))
            api.write_bytes(b"a" * 32)
            hmac.write_bytes(b"b" * 32)
            nanodep.write_bytes(b"c" * 32)
            send.write_bytes(b"d" * 32)
            recv.write_bytes(b"e" * 32)
            with mock.patch.object(stage_credentials, "root_parent"):
                with mock.patch.object(stage_credentials, "private_directory"):
                    with mock.patch.object(stage_credentials.os, "fchown"):
                        stage_credentials.stage(api, hmac, nanodep, nano, deus,
                                                base / "legacy", send, recv)
            for directory in (nano, deus):
                self.assertEqual((directory / "ddm-send-hmac").read_bytes(), b"d" * 32)
                self.assertEqual((directory / "ddm-recv-hmac").read_bytes(), b"e" * 32)
                for name in ("ddm-send-hmac", "ddm-recv-hmac"):
                    self.assertEqual((directory / name).stat().st_mode & 0o777, 0o600)

    def test_root_parent_rejects_symlink_and_world_writable_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            directory = base / "credentials"
            directory.mkdir(mode=0o777)
            directory.chmod(0o777)
            with self.assertRaises(ValueError):
                stage_credentials.root_parent(directory)
            link = base / "link"
            link.symlink_to(directory)
            with self.assertRaises(ValueError):
                stage_credentials.root_parent(link)


if __name__ == "__main__":
    unittest.main()
