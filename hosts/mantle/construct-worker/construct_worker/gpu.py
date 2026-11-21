"""Is the GPU someone else's right now? Read once per claim, two nvidia-smi calls.

Busy (no claim) when:
- a foreign compute (CUDA) process holds more than 1 GB of VRAM (--query-compute-apps lists compute contexts only, so
  the compositor doesn't count), or
- less than ~5 GB of VRAM is free, not counting our own processes: graphics-only users (games) never show up as compute
  apps, and large-v3 at float16 needs ~4.5 GB, so loading it next to them would run out of memory.
Utilisation doesn't count (desktop graphics alone run 10-46%); it is sent for display only.
"""

from __future__ import annotations

import os
import subprocess

FOREIGN_MB = 1024
NEED_FREE_MB = 5000
MAX_APPS = 20  # construct's GpuSchema limits


def _smi(nvidia_smi: str, query: str) -> list[list[str]]:
    out = subprocess.run([nvidia_smi, query, "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=10, check=True).stdout
    return [[c.strip() for c in line.split(",")] for line in out.splitlines() if line.strip()]


def _num(s: str) -> float:
    try:
        return float(s)
    except ValueError:  # "[N/A]"
        return 0.0


def _is_ollama(pid: int) -> bool:
    """Ollama's server and runners (a DynamicUser + PrivateUsers service, so nvidia-smi names them "[No data]")."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv0 = f.read().split(b"\0", 1)[0].decode(errors="replace")
    except OSError:
        return False
    return "ollama" in os.path.basename(argv0).lower()


def gpu_state(nvidia_smi: str = "nvidia-smi", own_pids: set[int] | None = None, own_ollama: bool = False) -> dict:
    """The claim body's `gpu` (construct's GpuSchema): `{busy, reason?, util, memUsedMb, foreignApps}`.
    `own_ollama`: right after our own title/tag job, Ollama's model is still leaving VRAM (keep_alive 0 takes a few
    seconds); count it as ours then, so the next job doesn't wait a poll on our own model."""
    own = {os.getpid(), *(own_pids or ())}
    try:
        util, used, total = (_num(v) for v in _smi(nvidia_smi, "--query-gpu=utilization.gpu,memory.used,memory.total")[0][:3])
        apps = [(int(_num(r[0])), os.path.basename(r[1]) or r[1], int(_num(r[2]))) for r in _smi(nvidia_smi, "--query-compute-apps=pid,process_name,used_memory") if len(r) >= 3]
    except (OSError, subprocess.SubprocessError, IndexError, ValueError) as e:
        return {"busy": True, "reason": f"GPU unreadable: {e}"[:120]}
    if own_ollama:
        own |= {pid for pid, _, _ in apps if _is_ollama(pid)}
    ours = sum(mb for pid, _, mb in apps if pid in own)
    heavy = sorted(((name, mb) for pid, name, mb in apps if pid not in own and mb > FOREIGN_MB), key=lambda a: -a[1])
    free = total - used + ours
    out = {
        "busy": False,
        "util": max(0, min(100, round(util))),
        "memUsedMb": max(0, int(used)),
        "foreignApps": [{"name": name[:80], "memMb": mb} for name, mb in heavy[:MAX_APPS]],
    }
    if heavy:
        out["busy"] = True
        out["reason"] = ("GPU in use: " + ", ".join(f"{name} {mb / 1024:.1f} GB" for name, mb in heavy))[:120]
    elif free < NEED_FREE_MB:
        out["busy"] = True
        out["reason"] = f"GPU in use: {free / 1024:.1f} GB free"
    return out
