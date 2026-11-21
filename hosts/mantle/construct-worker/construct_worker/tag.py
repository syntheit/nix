"""memos.tag: chapters and tags from the transcript, by the same small local model as titles (Ollama on mantle).

The payload (construct contract.ts TagPayload) carries the transcript's segments in ms and the tag vocabulary. Two
passes, each answered as JSON held to a schema (Ollama structured output):

1. Chapters. The transcript goes to the model as numbered lines, in windows of about WINDOW_CHARS for a long memo. For
   each window it gives its chapters (first line, one sentence of what is said, a title) and whether the first one
   continues the window before. Windows are merged (a continued chapter joins the one before), chapters shorter than
   MIN_CHAPTER_MS join a neighbour, and the chapters run without gaps from 0 to the memo's end.
2. Tags. The chapters' sentences, numbered, go to the model once more with the vocabulary: 0-3 tags each (an enum, so
   it cannot invent one) and at most one tag it would add. Tagging a one-line summary is what a 4B model does well;
   tagging while it reads the raw transcript, it tagged by the words it saw (battery life as Health).

Every answer is checked (lines in order and in range, titles present, one tag list per chapter, tags known) and asked
again once on garbage; a second failure ends the job with `{chapters: [], error}`, which construct stores as an error
line. construct checks the result again before storing it.
"""

from __future__ import annotations

import json
import logging
import re
import threading
import time
from collections.abc import Callable

from . import Stopped
from .title import Ollama, TitleError

log = logging.getLogger(__name__)

WINDOW_CHARS = 6000  # ~6-9 minutes of speech; with the instructions well inside num_ctx, Cyrillic included
MIN_CHAPTER_MS = 60_000
MAX_TAGS = 3
TITLE_CHARS = 80
NUM_CTX = 8192
TIMEOUT_S = 180


class TagError(TitleError):
    """Ollama failed (a retryable job error)."""


class Garbage(Exception):
    """The model's answer is unusable."""


def stamp(ms: int) -> str:
    s = max(0, int(ms) // 1000)
    h = s // 3600
    return f"{h}:{s % 3600 // 60:02d}:{s % 60:02d}" if h else f"{s // 60:02d}:{s % 60:02d}"


def windows(segments: list[dict], max_chars: int = WINDOW_CHARS) -> list[range]:
    """Consecutive runs of segment indices of at most `max_chars` characters of text (a longer segment is a run alone)."""
    out: list[range] = []
    start, size = 0, 0
    for i, s in enumerate(segments):
        n = len(s["text"]) + 12
        if i > start and size + n > max_chars:
            out.append(range(start, i))
            start, size = i, 0
        size += n
    if segments:
        out.append(range(start, len(segments)))
    return out


def most_chapters(minutes: float) -> int:
    """How many chapters a stretch of this many minutes may have: one per ~3 minutes, at least 1."""
    return max(1, round(minutes / 3))


# ── pass 1: chapters ────────────────────────────────────────────────


def chapter_prompt(part: tuple[int, int], previous: str | None, minutes: float) -> str:
    most = most_chapters(minutes)
    text = (
        "You split a voice memo's transcript into chapters. The transcript comes as numbered lines, each with the "
        "[mm:ss] where it starts.\n\n"
        "A chapter is a long stretch about one subject, usually three to ten minutes. Start a new chapter only where "
        "he moves to a clearly different subject, never for a new detail of the same one. "
        f"This text is about {max(1, round(minutes))} minutes long: give 1 to {most} chapter{'s' if most > 1 else ''}. "
        "For each chapter give:\n"
        "- start_line: the number of its first line. The first chapter starts at line 1; each next chapter starts "
        "after the one before.\n"
        "- about: one short sentence saying what he talks about there.\n"
        "- title: 2 to 7 words naming that, in sentence case (capitalise only the first word and names: "
        '"Moving savings into bonds", not "Moving Savings Into Bonds"), in the memo\'s own language (a Spanish memo '
        "gets Spanish titles), never a time stamp."
    )
    if part[1] > 1:
        text += f"\n\nThis is part {part[0]} of {part[1]} of a longer memo; the lines are numbered from 1 within this part."
        if previous:
            text += (
                f' The part before ended with the chapter "{previous}". continues: true when this part\'s first lines '
                "carry on with that same subject, else false."
            )
    return text


# One worked example per pass (a user turn and the answer).
CHAPTER_IN = (
    "1. [00:00] Okay so first the saddle, it's still too high and my knee hurts after the long ride on Sunday, I raised it last week and that was a mistake.\n"
    "2. [02:10] I'll drop it half a centimetre tonight and see how Thursday's ride feels, and if it still hurts I'll book the bike fit.\n"
    "3. [04:30] The other thing, I want to move the cash from the broker into the bond fund this month, the rate is still good and the peso keeps sliding.\n"
    "4. [07:50] So that's maybe two thousand dollars, keep three months of rent aside, the rest goes in."
)
CHAPTER_OUT = {
    "chapters": [
        {"start_line": 1, "about": "His saddle is too high and hurts his knee; he will lower it and test it on Thursday's ride.", "title": "Saddle height and knee pain"},
        {"start_line": 3, "about": "Moving the broker cash into the bond fund this month, keeping three months of rent aside.", "title": "Broker cash into the bond fund"},
    ]
}


def chapter_schema(ask_continues: bool) -> dict:
    chapter = {
        "type": "object",
        "properties": {
            "start_line": {"type": "integer"},
            # Said before the title: the model names the subject, then titles it. Pass 2 tags these sentences.
            "about": {"type": "string"},
            "title": {"type": "string"},
        },
        "required": ["start_line", "about", "title"],
    }
    props: dict = {}
    if ask_continues:
        props["continues"] = {"type": "boolean"}
    props["chapters"] = {"type": "array", "items": chapter, "minItems": 1}
    return {"type": "object", "properties": props, "required": list(props)}


def clean_title(raw: str) -> str:
    t = re.sub(r"\s+", " ", str(raw)).strip().strip("\"'`*#“”‘’«»").strip()
    t = re.sub(r"^\[?\d{1,2}(?::\d{2}){1,2}\]?\s*[-–—:]?\s*", "", t).rstrip(".").strip()
    if len(t) > TITLE_CHARS:
        t = t[: TITLE_CHARS - 1].rsplit(" ", 1)[0].rstrip(",;:-–— ") + "…"
    return t[:1].upper() + t[1:]


def parse(raw: str) -> dict:
    raw = re.sub(r"<think>.*?</think>", "", raw, flags=re.S).strip()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise Garbage(f"no JSON ({e.msg})") from None
    if not isinstance(data, dict):
        raise Garbage("not an object")
    return data


def check_chapters(raw: str, n_lines: int) -> dict:
    """A window's answer as {continues, chapters: [(line0, title, about)]}; raises Garbage."""
    data = parse(raw)
    if not isinstance(data.get("chapters"), list) or not data["chapters"]:
        raise Garbage("no chapters")
    out = []
    last = 0
    for k, c in enumerate(data["chapters"], 1):
        if not isinstance(c, dict):
            raise Garbage(f"chapter {k} is not an object")
        line = c.get("start_line")
        if not isinstance(line, int) or isinstance(line, bool):
            raise Garbage(f"chapter {k} has no start_line")
        if k == 1:
            line = 1  # the first chapter starts the window, whatever it says
        if line <= last or line > n_lines:
            # Out of order or past the window (a small model on a long memo, 21 Nov 2026): its lines stay in the chapter
            # before, instead of failing the whole memo's chapters.
            continue
        last = line
        title = clean_title(c.get("title") or "")
        if not title:
            raise Garbage(f"chapter {k} has no title")
        about = re.sub(r"\s+", " ", str(c.get("about") or "")).strip() or title
        out.append((line - 1, title, about))
    return {"continues": data.get("continues") is True, "chapters": out}


def merge(chapters: list[dict], duration_ms: int) -> list[dict]:
    """No gaps: each chapter ends where the next starts, the first starts at 0, the last ends at the memo's end. A chapter
    under MIN_CHAPTER_MS joins the one before (the first joins the next), keeping that one's title."""
    if not chapters:
        return []
    cs = [dict(c) for c in chapters]
    cs[0]["startMs"] = 0
    end = max(duration_ms, cs[-1]["startMs"] + 1)
    for i, c in enumerate(cs):
        c["endMs"] = cs[i + 1]["startMs"] if i + 1 < len(cs) else end
    i = 0
    while len(cs) > 1 and i < len(cs):
        c = cs[i]
        if c["endMs"] - c["startMs"] >= MIN_CHAPTER_MS:
            i += 1
            continue
        if i == 0:
            cs[1].update(startMs=c["startMs"], about=f"{c['about']} {cs[1]['about']}")
            del cs[0]
        else:
            cs[i - 1].update(endMs=c["endMs"], about=f"{cs[i - 1]['about']} {c['about']}")
            del cs[i]
    return cs


# ── pass 2: tags ────────────────────────────────────────────────────


def tag_prompt(vocabulary: list[dict]) -> str:
    tags = "\n".join(f"- {v['name']}: {v['hint']}" if v.get("hint") else f"- {v['name']}" for v in vocabulary)
    return (
        "You file the parts of Daniel's voice memos under tags. Each numbered line says what he talks about in one part. "
        "For each line, choose the tags from the list below that he would look under to find that part again. Judge "
        "by the subject, not by the words: a phone's battery life is not Health, choosing a phone is not Finance unless "
        "the money itself is the point, a device or an app is not Home, a motorbike is not Music. No tag is a catch-all: "
        "a part that is merely personal gets Journal only if he reflects on his own feelings, and a tag about his life "
        "as a whole only if he reviews his goals, routines or priorities. Usually one tag; two or three only when the "
        "part is truly about each; none when nothing fits.\n\n"
        f"Tags:\n{tags}\n\n"
        "Answer one entry per line, in order, with its number. new_tag: if a main subject of these parts fits none of "
        "the tags and would be a useful tag across many memos, one short name for it (one or two words, in English); "
        "otherwise null. Never a tag from the list."
    )


TAG_IN = (
    "1. His saddle is too high and hurts his knee; he will lower it and test it on Thursday's ride.\n"
    "2. Moving the broker cash into the bond fund this month, keeping three months of rent aside.\n"
    "3. Comparing two phones' screens and battery life before buying one for testing apps."
)
TAG_OUT = {"parts": [{"n": 1, "tags": ["Health", "Plan"]}, {"n": 2, "tags": ["Finance"]}, {"n": 3, "tags": ["Construct"]}], "new_tag": None}


def tag_schema(names: list[str], n: int) -> dict:
    part = {
        "type": "object",
        "properties": {"n": {"type": "integer"}, "tags": {"type": "array", "items": {"type": "string", "enum": names}, "maxItems": MAX_TAGS}},
        "required": ["n", "tags"],
    }
    return {
        "type": "object",
        "properties": {"parts": {"type": "array", "items": part, "minItems": n, "maxItems": n}, "new_tag": {"type": ["string", "null"]}},
        "required": ["parts", "new_tag"],
    }


def check_tags(raw: str, n: int, names: list[str], lenient: bool) -> dict:
    """{tags: [[name…] per chapter], new_tag}; raises Garbage. `lenient` (the second try) drops unknown and extra tags."""
    data = parse(raw)
    parts = data.get("parts")
    if not isinstance(parts, list) or len(parts) != n:
        raise Garbage(f"{len(parts) if isinstance(parts, list) else 'no'} tag entries for {n} chapters")
    known = {x.lower(): x for x in names}
    out: list[list[str]] = []
    for k, p in enumerate(parts, 1):
        # Entries are taken in order: the model's own numbering slips (a -1 now and then) and is not checked.
        if not isinstance(p, dict) or not isinstance(p.get("tags"), list):
            raise Garbage(f"entry {k} has no tags")
        tags: list[str] = []
        for t in p["tags"]:
            name = known.get(str(t).strip().lower())
            if not name:
                if lenient:
                    continue
                raise Garbage(f"entry {k} has an unknown tag {t!r}")
            if name not in tags:
                tags.append(name)
        if len(tags) > MAX_TAGS:
            if not lenient:
                raise Garbage(f"entry {k} has {len(tags)} tags")
            tags = tags[:MAX_TAGS]
        out.append(tags)
    new = data.get("new_tag")
    return {"tags": out, "new_tag": new.strip() if isinstance(new, str) and new.strip() else None}


def suggestion(name: str | None, names: list[str]) -> str | None:
    """A short name outside the vocabulary, or None."""
    if not name or len(name) > 24 or name.lower() in {x.lower() for x in names} | {"null", "none"}:
        return None
    return name


# ── the model ───────────────────────────────────────────────────────


def call(ollama: Ollama, messages: list[dict], fmt: dict, temperature: float) -> str:
    r = ollama.http.post(
        f"{ollama.url}/api/chat",
        json={
            "model": ollama.model,
            "messages": messages,
            "stream": False,
            "format": fmt,
            # Kept loaded between calls; make_chapters unloads it at the end (never left in VRAM next to whisper or a game).
            "keep_alive": "2m",
            "options": {"temperature": temperature, "num_predict": 1536, "num_ctx": NUM_CTX},
        },
        timeout=(10, TIMEOUT_S),
    )
    if r.status_code >= 400:
        raise TagError(f"ollama {r.status_code}: {r.text[:200]}")
    return r.json()["message"]["content"]


def in_thread(fn: Callable[[], str], tick: Callable[[float, str], bool], progress: float, reason: str) -> str:
    """Runs fn in a daemon thread so progress, the lease and shutdown keep ticking; Stopped when tick says stop."""
    box: dict = {}

    def run() -> None:
        try:
            box["v"] = fn()
        except Exception as e:  # noqa: BLE001 - handed back below
            box["e"] = e

    t = threading.Thread(target=run, name="ollama", daemon=True)
    t.start()
    while t.is_alive():
        t.join(1)
        if t.is_alive() and not tick(progress, reason):
            raise Stopped()
    if "e" in box:
        e = box["e"]
        if isinstance(e, TagError):
            raise e
        raise TagError(f"ollama: {type(e).__name__}: {e}") from e
    return box["v"]


def ask(ollama: Ollama, messages: list[dict], fmt: dict, check: Callable[[str, bool], dict], tick: Callable[[float, str], bool], progress: float, reason: str) -> tuple[dict | None, str]:
    """The checked answer, asking once more (warmer, lenient) on garbage; (None, why) after two bad answers."""
    problem = ""
    for attempt in range(2):
        raw = in_thread(lambda: call(ollama, messages, fmt, 0.2 if attempt == 0 else 0.5), tick, progress, reason)
        try:
            return check(raw, attempt == 1), ""
        except Garbage as e:
            problem = str(e)
            log.warning("%s, try %d: %s; answer: %s", reason, attempt + 1, e, raw[:300])
    return None, problem


def unload(ollama: Ollama) -> None:
    """Drops the model from VRAM (best effort)."""
    try:
        ollama.http.post(f"{ollama.url}/api/generate", json={"model": ollama.model, "keep_alive": 0}, timeout=(5, 30))
    except Exception:  # noqa: BLE001
        pass


def make_chapters(payload: dict, ollama: Ollama | None, tick: Callable[[float, str], bool], max_chars: int = WINDOW_CHARS) -> dict:
    """The job result `{chapters: [{startMs, endMs, title, tags}], suggest, model, error?}`. Raises TagError when Ollama
    fails (retryable), Stopped when tick says stop."""
    segments = [s for s in payload.get("segments") or [] if str(s.get("text") or "").strip()]
    if not segments:
        return {"chapters": [], "suggest": None}
    if not ollama:
        raise TagError("no Ollama configured")
    try:
        return run(segments, payload.get("vocabulary") or [], int(payload.get("durationMs") or segments[-1]["end"]), ollama, tick, max_chars)
    finally:
        unload(ollama)


def run(segments: list[dict], vocabulary: list[dict], duration: int, ollama: Ollama, tick: Callable[[float, str], bool], max_chars: int) -> dict:
    t0 = time.monotonic()
    names = [v["name"] for v in vocabulary]
    parts = windows(segments, max_chars)
    steps = len(parts) + 1
    failed = lambda what, why: {"chapters": [], "suggest": None, "model": ollama.model, "error": f"{ollama.model} gave unusable {what} twice ({why})"}  # noqa: E731

    found: list[dict] = []
    for w, idx in enumerate(parts):
        previous = found[-1]["title"] if found else None
        minutes = (segments[idx[-1]]["end"] - (0 if w == 0 else segments[idx[0]]["start"])) / 60_000
        lines = "\n".join(f"{k}. [{stamp(segments[i]['start'])}] {segments[i]['text'].strip()[:max_chars]}" for k, i in enumerate(idx, 1))
        messages = [
            {"role": "system", "content": chapter_prompt((w + 1, len(parts)), previous, minutes)},
            {"role": "user", "content": CHAPTER_IN},
            {"role": "assistant", "content": json.dumps(CHAPTER_OUT)},
            {"role": "user", "content": lines},
        ]
        answer, why = ask(ollama, messages, chapter_schema(previous is not None), lambda raw, _: check_chapters(raw, len(idx)), tick, w / steps, f"chapters {w + 1}/{len(parts)}")
        if answer is None:
            return failed("chapters", f"part {w + 1} of {len(parts)}: {why}")
        for k, (line0, title, about) in enumerate(answer["chapters"]):
            prev = found[-1] if found else None
            if k == 0 and prev and (answer["continues"] or title.lower() == prev["title"].lower()):
                prev["about"] += f" {about}"
                continue
            found.append({"startMs": int(segments[idx[line0]]["start"]), "title": title, "about": about})
    chapters = merge(found, duration)

    if names:
        listing = "\n".join(f"{k}. {c['about']}" for k, c in enumerate(chapters, 1))
        messages = [
            {"role": "system", "content": tag_prompt(vocabulary)},
            *([{"role": "user", "content": TAG_IN}, {"role": "assistant", "content": json.dumps(TAG_OUT)}] if {"Health", "Plan", "Finance", "Construct"} <= set(names) else []),
            {"role": "user", "content": listing},
        ]
        tagged, why = ask(ollama, messages, tag_schema(names, len(chapters)), lambda raw, lenient: check_tags(raw, len(chapters), names, lenient), tick, len(parts) / steps, "tags")
        if tagged is None:
            return failed("tags", why)
    else:
        tagged = {"tags": [[] for _ in chapters], "new_tag": None}

    out = [{"startMs": c["startMs"], "endMs": c["endMs"], "title": c["title"], "tags": t} for c, t in zip(chapters, tagged["tags"])]
    log.info("chapters in %.1fs (%d parts): %s", time.monotonic() - t0, len(parts), "; ".join(f"{stamp(c['startMs'])} {c['title']} {c['tags']}" for c in out))
    return {"chapters": out, "suggest": suggestion(tagged["new_tag"], names), "model": ollama.model}
