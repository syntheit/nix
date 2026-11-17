"""memos.title: a short title from the transcript, by a small local model on Ollama, else the first sentence.

The model is pulled on first use and unloaded right after each request (keep_alive 0), so it never sits in VRAM
next to whisper or a game, and Ollama counts as a foreign GPU user only while someone else uses it.
"""

from __future__ import annotations

import json
import logging
import re
import time
from collections.abc import Callable

import requests

from . import Stopped

log = logging.getLogger(__name__)

MAX_WORDS = 8
MAX_CHARS = 8000  # ~2k tokens of transcript is plenty for a title
SYSTEM = (
    "You title voice memos. Reply with the title only: at most 8 words, sentence case (capitalise only the first word "
    "and proper nouns), no quotes, no trailing period, no preamble. Use the memo's language."
)
EXAMPLES = [
    ("ok so the plan for saturday is the asado at fede's place, I need to buy the meat friday and charcoal", "Saturday asado at Fede's: meat and charcoal"),
    ("reminder to call the bank about the transfer limit before the end of the month", "Call the bank about the transfer limit"),
]


def clean(raw: str) -> str:
    """The first line of a model reply, as a title: no think block, quotes, label or trailing period; ≤ 8 words."""
    raw = re.sub(r"<think>.*?</think>", "", raw, flags=re.S)
    line = next((l for l in (x.strip() for x in raw.splitlines()) if l), "")
    line = re.sub(r"^(title\s*:\s*)", "", line, flags=re.I)
    line = line.strip(" \t\"'`*#“”‘’«»").rstrip(".").strip()
    words = line.split()
    if len(words) > MAX_WORDS:
        line = " ".join(words[:MAX_WORDS]).rstrip(",;:-–—")
    return line[:1].upper() + line[1:]


def fallback(text: str) -> str:
    """The first sentence, trimmed to 8 words."""
    first = re.split(r"(?<=[.!?…])\s+|\n", text.strip(), maxsplit=1)[0] if text.strip() else ""
    return clean(first) or "Voice memo"


class Ollama:
    def __init__(self, url: str, model: str):
        self.url = url.rstrip("/")
        self.model = model
        self.http = requests.Session()

    def has_model(self) -> bool:
        r = self.http.post(f"{self.url}/api/show", json={"model": self.model}, timeout=10)
        if r.status_code == 404:
            return False
        r.raise_for_status()
        return True

    def pull(self, tick: Callable[[float, str], bool]) -> None:
        """Downloads the model (~2.5 GB), reporting progress through tick; Stopped when tick says stop."""
        log.info("pulling %s", self.model)
        with self.http.post(f"{self.url}/api/pull", json={"model": self.model, "stream": True}, stream=True, timeout=(10, 120)) as r:
            r.raise_for_status()
            for line in r.iter_lines():
                if not line:
                    continue
                msg = json.loads(line)
                if msg.get("error"):
                    raise RuntimeError(f"pull: {msg['error']}")
                done, total = msg.get("completed") or 0, msg.get("total") or 0
                if not tick(done / total * 0.9 if total else 0.0, f"downloading {self.model}"):
                    raise Stopped()
                if msg.get("status") == "success":
                    return

    def title(self, text: str) -> str:
        messages = [{"role": "system", "content": SYSTEM}]
        for memo, title in EXAMPLES:
            messages += [{"role": "user", "content": memo}, {"role": "assistant", "content": title}]
        messages.append({"role": "user", "content": text[:MAX_CHARS]})
        r = self.http.post(
            f"{self.url}/api/chat",
            json={
                "model": self.model,
                "messages": messages,
                "stream": False,
                "keep_alive": 0,
                "options": {"temperature": 0.2, "num_predict": 40, "num_ctx": 4096},
            },
            timeout=180,
        )
        r.raise_for_status()
        return clean(r.json()["message"]["content"])


def make_title(text: str, ollama: Ollama | None, tick: Callable[[float, str], bool]) -> dict:
    """The job result `{title}`, plus how it was made (`source`, `model`)."""
    if ollama and text.strip():
        try:
            if not ollama.has_model():
                ollama.pull(tick)
            if not tick(0.9, "titling"):
                raise Stopped()
            t0 = time.monotonic()
            title = ollama.title(text)
            if title:
                log.info("title in %.1fs: %s", time.monotonic() - t0, title)
                return {"title": title, "source": "ollama", "model": ollama.model}
            log.warning("empty title from %s; using the first sentence", ollama.model)
        except (requests.RequestException, RuntimeError, KeyError, ValueError) as e:
            log.warning("ollama failed (%s); using the first sentence", e)
    return {"title": fallback(text), "source": "first-sentence"}
