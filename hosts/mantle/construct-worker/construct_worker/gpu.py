"""Is the GPU someone else's right now? The rule: a foreign compute process holding more than 1 GB of VRAM, or GPU
utilisation averaging over 30% across the last 60 s, means busy (no claim). Samples taken while this worker runs a job
are dropped, so its own work never makes it look busy afterwards."""

from __future__ import annotations

import collections
import logging
import os
import subprocess
import threading
import time

log = logging.getLogger(__name__)

FOREIGN_MB = 1024
UTIL_PCT = 30
WINDOW_S = 60
SAMPLE_S = 5


def _smi(nvidia_smi: str, *query: str) -> list[list[str]]:
    out = subprocess.run([nvidia_smi, *query, "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=10, check=True).stdout
    return [[c.strip() for c in line.split(",")] for line in out.splitlines() if line.strip()]


def _num(s: str) -> float:
    try:
        return float(s)
    except ValueError:  # "[N/A]"
        return 0.0


class GpuMonitor:
    def __init__(self, nvidia_smi: str = "nvidia-smi"):
        self.nvidia_smi = nvidia_smi
        self.samples: collections.deque[tuple[float, float]] = collections.deque()
        self.mem_used_mb = 0
        self.error: str | None = None
        self._paused = False
        self._lock = threading.Lock()

    def start(self) -> None:
        threading.Thread(target=self._loop, name="gpu-sampler", daemon=True).start()

    def _loop(self) -> None:
        while True:
            self.sample()
            time.sleep(SAMPLE_S)

    def sample(self) -> None:
        try:
            util, mem = (_num(v) for v in _smi(self.nvidia_smi, "--query-gpu=utilization.gpu,memory.used")[0][:2])
        except (OSError, subprocess.SubprocessError, IndexError, ValueError) as e:
            with self._lock:
                self.error = f"nvidia-smi: {e}"
            return
        now = time.monotonic()
        with self._lock:
            self.error = None
            self.mem_used_mb = int(mem)
            if not self._paused:
                self.samples.append((now, util))
            while self.samples and self.samples[0][0] < now - WINDOW_S:
                self.samples.popleft()

    def pause(self) -> None:
        """Our own job starts: stop counting utilisation."""
        with self._lock:
            self._paused = True
            self.samples.clear()

    def resume(self) -> None:
        with self._lock:
            self._paused = False
            self.samples.clear()

    def foreign_apps(self, own_pids: set[int]) -> list[dict]:
        apps = []
        for row in _smi(self.nvidia_smi, "--query-compute-apps=pid,process_name,used_memory"):
            if len(row) < 3:
                continue
            pid = int(_num(row[0]))
            if pid in own_pids:
                continue
            apps.append({"name": os.path.basename(row[1]) or row[1], "memMb": int(_num(row[2]))})
        return apps

    def state(self, own_pids: set[int] | None = None) -> dict:
        """The claim body's `gpu`: `{busy, reason?}` (what construct reads) plus the numbers behind it."""
        own = {os.getpid(), *(own_pids or ())}
        try:
            apps = self.foreign_apps(own)
        except (OSError, subprocess.SubprocessError, ValueError) as e:
            return {"busy": True, "reason": "GPU unreadable", "detail": f"nvidia-smi: {e}"[:200]}
        with self._lock:
            if self.error:
                return {"busy": True, "reason": "GPU unreadable", "detail": self.error[:200]}
            util = sum(u for _, u in self.samples) / len(self.samples) if self.samples else 0.0
            mem = self.mem_used_mb
        heavy = [a for a in apps if a["memMb"] > FOREIGN_MB]
        busy = bool(heavy) or util > UTIL_PCT
        out = {"busy": busy, "util": round(util), "memUsedMb": mem, "foreignApps": apps}
        if busy:
            out["reason"] = "GPU in use"
            out["detail"] = ", ".join(f"{a['name']} {a['memMb']} MB" for a in heavy) or f"utilisation {round(util)}% over {WINDOW_S}s"
        return out
