"""memos.title: a short title from the transcript, by a small local model on Ollama.

The model is pulled by services.ollama.loadModels (construct-worker.nix) and unloaded right after each request
(keep_alive 0), so it never sits in VRAM next to whisper or a game. An Ollama failure is a retryable job error; until a
title arrives construct shows the memo's first sentence. Empty text gets an empty title (construct keeps its own).
"""

from __future__ import annotations

import logging
import re
import threading
import time
from collections.abc import Callable

import requests

from . import Stopped

log = logging.getLogger(__name__)

MAX_WORDS = 12
MAX_CHARS = 16000  # a guard: construct's sample is at most ~9,100 characters (6 excerpts with stamps), all of it read
TIMEOUT_S = 120
SYSTEM = (
    "You title voice memos. Reply with the title only: at most 12 words that name the memo's main topics (join two or "
    "three with commas or 'and' when it covers several), sentence case (capitalise only the first word and proper "
    "nouns), no quotes, no trailing period, no preamble. Write the title in the memo's own language (a Spanish memo "
    "gets a Spanish title, a Russian one a Russian title), whatever the language of these instructions. A long memo "
    "comes as disjoint excerpts taken evenly from its start to its end, one per line, each starting with the [mm:ss] "
    "where it begins; the gaps between them are not shown. Title the whole memo from all the excerpts, not the first "
    "one, and never put a time in the title."
)
EXAMPLES = [
    ("ok so the plan for saturday is the asado at fede's place, I need to buy the meat friday and charcoal", "Saturday asado at Fede's: meat and charcoal"),
    (
        "[00:00] bueno, primero lo del asiento de la bici, sigue muy alto y me duele la rodilla después de la salida larga\n"
        "[12:40] y con la cartera quiero pasar la plata del broker al fondo de bonos este mes\n"
        "[25:10] después el viaje a Tiflis, tengo que ver si el auto puede quedarse en Georgia después de la visa",
        "Altura del asiento, pasar la plata a bonos y el auto en Tiflis",
    ),
]


# A leading time stamp copied from the excerpts: "[00:00] …", "(1:02:03) …", "00:00 – …" (same as construct's
# LEADING_STAMP; a bare "10:30 meeting" is kept).
STAMP = re.compile(r"^(?:[\[(]\d{1,2}(?::\d{2}){1,2}[\])]\s*[-–—:]?\s*|\d{1,2}(?::\d{2}){1,2}\s*[-–—]\s*)")


class TitleError(Exception):
    """Ollama failed or answered nothing usable: worth another attempt."""


def clean(raw: str) -> str:
    """The first line of a model reply, as a title: no think block, time stamp, quotes, label or trailing period; ≤ 12 words."""
    raw = re.sub(r"<think>.*?</think>", "", raw, flags=re.S)
    line = next((l for l in (x.strip() for x in raw.splitlines()) if l), "")
    junk = " \t\"'`*#“”‘’«»"
    line = line.strip(junk)
    line = re.sub(r"^(title\s*:\s*)", "", line, flags=re.I)
    line = STAMP.sub("", line)
    line = line.strip(junk).rstrip(".").strip()
    words = line.split()
    if len(words) > MAX_WORDS:
        line = " ".join(words[:MAX_WORDS]).rstrip(",;:-–—")
    return line[:1].upper() + line[1:]


class Ollama:
    def __init__(self, url: str, model: str):
        self.url = url.rstrip("/")
        self.model = model
        self.http = requests.Session()

    def title(self, text: str) -> str:
        messages = [{"role": "system", "content": SYSTEM}]
        for memo, title in EXAMPLES:
            messages += [{"role": "user", "content": memo}, {"role": "assistant", "content": title}]
        # The system prompt explains the excerpt form; the user turn is the memo alone, so nothing in it is English
        # but the memo (an English header pulled Spanish and Russian titles into English).
        messages.append({"role": "user", "content": text[:MAX_CHARS]})
        r = self.http.post(
            f"{self.url}/api/chat",
            json={
                "model": self.model,
                "messages": messages,
                "stream": False,
                "keep_alive": 0,
                "options": {"temperature": 0.2, "num_predict": 64, "num_ctx": 8192},
            },
            timeout=(10, TIMEOUT_S),
        )
        if r.status_code >= 400:
            raise TitleError(f"ollama {r.status_code}: {r.text[:200]}")
        return clean(r.json()["message"]["content"])


def make_title(text: str, ollama: Ollama | None, tick: Callable[[float, str], bool], excerpts: bool = False) -> dict:
    """The job result `{title}` (plus `model`). `excerpts`: the text is construct's sample of a long memo (one
    [mm:ss]-stamped excerpt per line), not the whole memo. Raises TitleError on failure, Stopped when tick says stop."""
    if not text.strip():
        return {"title": ""}
    if not ollama:
        raise TitleError("no Ollama configured")
    t0 = time.monotonic()
    # The request runs in a (daemon) thread so progress, the lease and shutdown keep ticking while the model loads.
    box: dict = {}

    def call() -> None:
        try:
            box["title"] = ollama.title(text)
        except Exception as e:  # noqa: BLE001 - handed to the job thread below
            box["error"] = e

    worker = threading.Thread(target=call, name="ollama", daemon=True)
    worker.start()
    while worker.is_alive():
        worker.join(1)
        if worker.is_alive() and not tick(0.5, "titling"):
            raise Stopped()
    if "error" in box:
        e = box["error"]
        if isinstance(e, TitleError):
            raise e
        raise TitleError(f"ollama: {type(e).__name__}: {e}") from e
    title = box["title"]
    if not title:
        raise TitleError(f"{ollama.model} answered no title")
    log.info("title in %.1fs%s: %s", time.monotonic() - t0, " (excerpts)" if excerpts else "", title)
    return {"title": title, "model": ollama.model}
