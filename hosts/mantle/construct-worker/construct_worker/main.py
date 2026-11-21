"""The worker loop: claim every 15 s (also the heartbeat), run one job at a time, report progress every ~20 s.

    construct-worker                                   # the service
    construct-worker --once                            # claim one job (if any), run it, exit
    construct-worker --once --file memo.m4a [--language es]   # dry run: transcribe locally, print the result JSON
    construct-worker --once --title "transcript text"         # dry run: title it, print the result JSON
    construct-worker --once --chapters payload.json           # dry run: chapters and tags for a memos.tag payload
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import signal
import socket
import sys
import tempfile
import time
from pathlib import Path

import requests

from . import Stopped
from .api import Construct, Lost, Unauthorized
from .gpu import gpu_state
from .tag import make_chapters
from .title import Ollama, TitleError, make_title
from .transcribe import TranscribeError, transcribe

log = logging.getLogger("construct_worker")

KINDS = ["memos.transcribe", "memos.title", "memos.tag"]
# Jobs that load Ollama's model, and how long after one its VRAM still counts as ours (keep_alive 0 unloads in seconds).
OLLAMA_KINDS = ("memos.title", "memos.tag")
OLLAMA_GRACE_S = 60
CLAIM_S = 15
PROGRESS_S = 20
# After a failed or released run, no claims for this long (then the longer one while failures keep coming), so a broken
# job or a full GPU doesn't burn the three attempts within a minute.
BACKOFF_S = [120, 600]


class Shutdown(Exception):
    pass


class Job:
    """One claimed job: `tick()` posts progress every ~20 s and heartbeats every 15 s; False means stop."""

    def __init__(self, worker: Worker, job: dict):
        self.w = worker
        self.id = job["id"]
        self.kind = job["kind"]
        self.payload = job.get("payload") or {}
        self.blobs = job.get("blobs") or []
        self.child_pids: set[int] = set()
        self.last_progress = 0.0
        self.last_beat = time.monotonic()
        self.stop: str | None = None

    def tick(self, progress: float, reason: str | None) -> bool:
        if self.w.shutdown:
            raise Shutdown()
        now = time.monotonic()
        if now - self.last_progress >= PROGRESS_S:
            self.last_progress = now
            try:
                sig = self.w.api.progress(self.id, progress, reason)
            except Lost as e:
                self.stop = f"lost ({e})"
                return False
            except (requests.RequestException, Unauthorized) as e:
                log.warning("job %s: progress failed: %s", self.id, e)
            else:
                if sig.get("cancel") or sig.get("hold"):
                    self.stop = "cancelled" if sig.get("cancel") else "taken back"
                    return False
        if now - self.last_beat >= CLAIM_S:
            self.last_beat = now
            self.w.heartbeat(self)
        return True


class Worker:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.host = args.host
        self.api = Construct(args.url, Path(args.token_file)) if args.token_file else None
        self.ollama = Ollama(args.ollama_url, args.ollama_model) if args.ollama_url else None
        self.shutdown = False
        self.next_job: dict | None = None
        self.failures = 0
        self.pause_until = 0.0
        self._last_busy: str | None = None
        # Until then Ollama's VRAM counts as ours: the model of the title/tag job that just ended is still unloading.
        self.ollama_until = 0.0

    def gpu(self, own: set[int] | None = None) -> dict:
        return gpu_state(self.args.nvidia_smi, own, own_ollama=time.monotonic() < self.ollama_until)

    # ── jobs ─────────────────────────────────────────────────────────

    def run_transcribe(self, job: Job) -> dict:
        sha = job.payload.get("audioSha")
        blob = next((b for b in job.blobs if b["sha256"] == sha), job.blobs[0] if job.blobs else None)
        if not blob:
            raise TranscribeError(f"job has no audio blob ({sha})", retry=False)
        with tempfile.TemporaryDirectory(prefix="construct-worker-") as tmp:
            path = Path(tmp) / f"audio.{blob.get('ext') or 'bin'}"
            self.api.download(blob["url"], path, lambda: job.tick(0.0, "downloading"))
            log.info("job %s: %s, %.1f MB", job.id, path.name, path.stat().st_size / 1e6)
            return transcribe(path, job.payload.get("language") or None, job.tick, job.child_pids.add)

    def run_title(self, job: Job) -> dict:
        return make_title(str(job.payload.get("text") or ""), self.ollama, job.tick, bool(job.payload.get("excerpts")))

    def run_tag(self, job: Job) -> dict:
        return make_chapters(job.payload, self.ollama, job.tick)

    def run(self, raw: dict) -> None:
        try:
            self._run(raw)
        finally:
            if raw.get("kind") in OLLAMA_KINDS:
                self.ollama_until = time.monotonic() + OLLAMA_GRACE_S

    def _run(self, raw: dict) -> None:
        job = Job(self, raw)
        log.info("job %s: %s claimed", job.id, job.kind)
        t0 = time.monotonic()
        try:
            if job.kind == "memos.transcribe":
                result = self.run_transcribe(job)
            elif job.kind == "memos.title":
                result = self.run_title(job)
            elif job.kind == "memos.tag":
                result = self.run_tag(job)
            else:
                raise TranscribeError(f"this worker does not run {job.kind}", retry=False)
            body = {"ok": True, "result": result}
            log.info("job %s: done in %.1fs%s", job.id, time.monotonic() - t0, f" (rtf {result['rtf']})" if result.get("rtf") else "")
        except Stopped:
            log.info("job %s: %s, dropped", job.id, job.stop or "stopped")
            return
        except Lost as e:
            log.info("job %s: lost (%s), dropped", job.id, e)
            return
        except Shutdown:
            log.info("job %s: stopping, handing it back", job.id)
            body = {"ok": False, "release": True}
        except TranscribeError as e:
            log.warning("job %s: %s", job.id, e)
            body = {"ok": False, "release": True} if e.release else {"ok": False, "error": str(e), "retry": e.retry}
            self.back_off(str(e))
        except TitleError as e:
            log.warning("job %s: %s", job.id, e)
            body = {"ok": False, "error": str(e), "retry": True}
            self.back_off(str(e))
        except Exception as e:  # noqa: BLE001 - report anything else as retryable rather than leave the lease to run out
            log.exception("job %s failed", job.id)
            body = {"ok": False, "error": f"{type(e).__name__}: {e}", "retry": True}
            self.back_off(str(e))
        if body["ok"]:
            self.failures = 0
        self.report(job, body)

    def back_off(self, why: str) -> None:
        wait = BACKOFF_S[min(self.failures, len(BACKOFF_S) - 1)]
        self.failures += 1
        self.pause_until = time.monotonic() + wait
        log.info("no claims for %d min after: %s", wait // 60, why[:200])

    def report(self, job: Job, body: dict) -> None:
        """Posts the result. A release (no attempt used) needs a construct that knows it: an older one answers 400 (its
        error field is required, so `release` is sent without one), and then it goes as a retryable error."""
        try:
            try:
                state = self.api.result(job.id, body).get("state")
            except requests.HTTPError as e:
                if not (body.get("release") and e.response is not None and e.response.status_code == 400):
                    raise
                log.info("job %s: construct can't release jobs yet; reporting a retryable stop", job.id)
                state = self.api.result(job.id, {"ok": False, "error": f"the worker on {self.host} handed it back", "retry": True}).get("state")
            log.info("job %s: reported, now %s", job.id, state)
        except Lost as e:
            log.info("job %s: result not taken (%s)", job.id, e)
        except (requests.RequestException, Unauthorized) as e:
            log.error("job %s: reporting the result failed: %s", job.id, e)

    # ── the loop ─────────────────────────────────────────────────────

    def heartbeat(self, job: Job) -> None:
        """A claim while a job runs: keeps the host online in construct. It hands out no job while we hold one, unless our
        lease ran out meanwhile; a job it does hand out runs next."""
        try:
            got = self.api.claim(self.host, KINDS, {**self.gpu(job.child_pids), "busy": False})
        except (requests.RequestException, Unauthorized, Lost, ValueError) as e:
            log.warning("heartbeat failed: %s", e)
            return
        if got.get("job") and not self.next_job:
            log.warning("job %s handed out while job %s runs; it runs next", got["job"]["id"], job.id)
            self.next_job = got["job"]

    def claim(self) -> dict | None:
        if self.next_job:
            job, self.next_job = self.next_job, None
            return job
        gpu = self.gpu()
        left = self.pause_until - time.monotonic()
        if left > 0 and not gpu["busy"]:
            # Still a heartbeat; busy keeps construct from handing out a job and says why.
            gpu = {**gpu, "busy": True, "reason": f"pausing {max(1, round(left / 60))} min after a failed job"}
        busy = gpu.get("reason") if gpu["busy"] else None
        if busy != self._last_busy:
            if busy:
                log.info("not claiming: %s", busy)
            else:
                log.info("claiming")
            self._last_busy = busy
        try:
            got = self.api.claim(self.host, KINDS, gpu)
        except Unauthorized as e:
            log.error("%s", e)
            return None
        except (requests.RequestException, Lost, ValueError) as e:
            log.warning("claim failed: %s", e)
            return None
        return got.get("job")

    def loop(self, once: bool) -> None:
        log.info("worker %s: %s at %s", self.host, ", ".join(KINDS), self.args.url)
        while not self.shutdown:
            job = self.claim()
            if job:
                self.run(job)
                if once:
                    return
                continue
            if once:
                log.info("no job")
                return
            for _ in range(CLAIM_S * 2):
                if self.shutdown:
                    break
                time.sleep(0.5)


def dry_run(args: argparse.Namespace) -> int:
    def tick(p: float, reason: str) -> bool:
        nonlocal last
        if (p, reason) != last:
            last = (p, reason)
            log.debug("%3.0f%% %s", p * 100, reason)
        return True

    last = None
    if args.file:
        t0 = time.monotonic()
        result = transcribe(Path(args.file), args.language, tick)
        log.info("wall %.1fs, load %.1fs, transcribe %.1fs, rtf %s", time.monotonic() - t0, result["params"]["load_s"], result["params"]["transcribe_s"], result["rtf"])
    else:
        ollama = Ollama(args.ollama_url, args.ollama_model) if args.ollama_url else None
        try:
            if args.chapters:
                result = make_chapters(json.loads(Path(args.chapters).read_text()), ollama, tick)
            else:
                result = make_title(args.title, ollama, tick)
        except TitleError as e:
            log.error("%s", e)
            return 1
    json.dump(result, sys.stdout, ensure_ascii=False, indent=None if args.file else 2)
    sys.stdout.write("\n")
    return 0


def main() -> None:
    env = os.environ.get
    p = argparse.ArgumentParser(prog="construct-worker", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--url", default=env("CONSTRUCT_URL", "http://raven:4322"), help="construct's base URL")
    p.add_argument("--token-file", default=env("CONSTRUCT_TOKEN_FILE"), help="file holding the worker token (cw_…)")
    p.add_argument("--host", default=env("WORKER_HOST", socket.gethostname()))
    p.add_argument("--ollama-url", default=env("OLLAMA_URL", "http://127.0.0.1:11434"))
    p.add_argument("--ollama-model", default=env("OLLAMA_MODEL", "qwen3:4b-instruct-2507-q4_K_M"))
    p.add_argument("--nvidia-smi", default=env("NVIDIA_SMI", "nvidia-smi"))
    p.add_argument("--once", action="store_true", help="one claim (or, with --file/--title, a local dry run), then exit")
    p.add_argument("--file", help="with --once: transcribe this file locally and print the result; construct is not contacted")
    p.add_argument("--language", default=None, help="with --file: language code (default: detect)")
    p.add_argument("--title", help="with --once: title this text locally and print the result")
    p.add_argument("--chapters", help="with --once: chapters and tags for this memos.tag payload (JSON file), printed")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args()

    journal = "JOURNAL_STREAM" in os.environ
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s" if journal else "%(asctime)s %(levelname)s %(message)s",
        stream=sys.stderr,
    )
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    logging.getLogger("faster_whisper").setLevel(logging.WARNING)

    if args.file or args.title is not None or args.chapters:
        if not args.once:
            p.error("--file, --title and --chapters are dry runs: add --once")
        sys.exit(dry_run(args))
    if not args.token_file:
        p.error("no token file: set CONSTRUCT_TOKEN_FILE or --token-file")

    worker = Worker(args)

    def stop(signum, _frame):
        log.info("signal %s: stopping", signum)
        worker.shutdown = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    worker.loop(args.once)


if __name__ == "__main__":
    main()
