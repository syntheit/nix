"""construct's worker API (app/server/job-routes.ts): claim, progress, result, blob download."""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from pathlib import Path

import requests

from . import Stopped

log = logging.getLogger(__name__)


class Lost(Exception):
    """The job is no longer ours (403/404/409): drop it without reporting."""


class Unauthorized(Exception):
    """The token is missing, revoked or belongs to another host."""


LOST = (403, 404, 409)


class Construct:
    def __init__(self, base_url: str, token_file: Path, timeout: float = 30):
        self.base = base_url.rstrip("/")
        self.token_file = token_file
        self.timeout = timeout
        self.http = requests.Session()
        self._token: str | None = None

    def _auth(self) -> dict[str, str]:
        if self._token is None:
            try:
                token = self.token_file.read_text().strip()
            except OSError as e:
                raise Unauthorized(f"cannot read the token file {self.token_file}: {e}") from e
            if not token.startswith("cw_"):
                raise Unauthorized(f"{self.token_file} holds no worker token (create one on raven: construct worker-token mantle)")
            self._token = token
        return {"Authorization": f"Bearer {self._token}"}

    def _post(self, path: str, body: dict, lost: tuple[int, ...] = ()) -> dict:
        r = self.http.post(self.base + path, json=body, headers=self._auth(), timeout=self.timeout)
        # A job call answers 403 once another host holds the job (workerMayCall), 409 when it was taken back.
        if r.status_code in lost:
            raise Lost(f"{path}: {r.status_code} {r.text[:200]}")
        if r.status_code in (401, 403):
            self._token = None  # re-read the file next time: the token may have been rotated
            raise Unauthorized(f"{path}: {r.status_code} {r.text[:200]}")
        r.raise_for_status()
        return r.json()

    def claim(self, host: str, kinds: list[str], gpu: dict) -> dict:
        """`{job: {...} | None, held: bool}`. Also the heartbeat."""
        return self._post("/api/jobs/worker/claim", {"host": host, "kinds": kinds, "gpu": gpu})

    def progress(self, job_id: int, progress: float, reason: str | None) -> dict:
        """`{cancel, hold}`: stop on either. Renews the 2-minute lease."""
        p = max(0.0, min(1.0, progress))
        return self._post(f"/api/jobs/{job_id}/progress", {"progress": round(p, 4), "reason": reason[:200] if reason else None}, LOST)

    def result(self, job_id: int, body: dict) -> dict:
        return self._post(f"/api/jobs/{job_id}/result", body, LOST)

    def download(self, url: str, dest: Path, tick: Callable[[], bool], limit_s: float = 600) -> None:
        """Streams a blob to `dest`, calling tick() per chunk (progress, lease, shutdown); False from it raises Stopped.
        Each read times out after `timeout`, the whole download after `limit_s`."""
        deadline = time.monotonic() + limit_s
        with self.http.get(self.base + url, headers=self._auth(), timeout=self.timeout, stream=True) as r:
            if r.status_code in (403, 404):
                raise Lost(f"{url}: {r.status_code}")
            r.raise_for_status()
            with dest.open("wb") as f:
                for chunk in r.iter_content(256 << 10):
                    f.write(chunk)
                    if not tick():
                        raise Stopped()
                    if time.monotonic() > deadline:
                        raise requests.Timeout(f"downloading {url} took over {limit_s:.0f}s")
