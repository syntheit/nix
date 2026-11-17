"""memos.transcribe: faster-whisper large-v3 on CUDA, in a child process per job.

The child loads the model, transcribes and exits, so the ~4.5 GB of VRAM is held only while a memo is being
transcribed, and stopping a job (cancel, hold) is a kill. It reports progress (last segment end / duration) on a pipe;
the parent polls `tick(progress, reason)` about once a second and stops when it returns False.
"""

from __future__ import annotations

import logging
import multiprocessing as mp
import re
import time
from collections.abc import Callable
from pathlib import Path

from . import Stopped

log = logging.getLogger(__name__)

MODEL = "large-v3"
SAMPLE_RATE = 16000
PARAMS = {"beam_size": 5, "vad_filter": True, "word_timestamps": True}
COMPUTE = {"device": "cuda", "compute_type": "float16"}
# Loud enough to be speech: 0.5 s worth of 100 ms frames above -40 dBFS.
LOUD_DBFS = -40.0
LOUD_SECONDS = 0.5
MAX_REPEATS = 3


class TranscribeError(Exception):
    def __init__(self, message: str, retry: bool):
        super().__init__(message)
        self.retry = retry


# ── the child ───────────────────────────────────────────────────────


def _norm(text: str) -> str:
    return re.sub(r"[\W_]+", " ", text.lower()).strip()


def _loud_seconds(audio) -> float:
    import numpy as np

    frame = SAMPLE_RATE // 10
    n = len(audio) // frame
    if n == 0:
        return 0.0
    rms = np.sqrt(np.mean(np.square(audio[: n * frame].reshape(n, frame), dtype=np.float64), axis=1))
    return float(np.count_nonzero(20 * np.log10(np.maximum(rms, 1e-10)) > LOUD_DBFS)) / 10


def problem_with(segments: list[dict], loud_s: float) -> str | None:
    """Why a pass looks broken, or None: no text from audio with speech in it, or the same segment over and over."""
    if not any(s["text"].strip() for s in segments) and loud_s >= LOUD_SECONDS:
        return "no segments from non-silent audio"
    run, prev = 0, None
    for s in segments:
        t = _norm(s["text"])
        run = run + 1 if t and t == prev else 1
        prev = t
        if run > MAX_REPEATS:
            return f"repetition loop: {s['text'].strip()[:60]!r}"
    return None


def _pass(model, audio, duration: float, language: str | None, condition: bool, out, attempt: int):
    segs_iter, info = model.transcribe(audio, language=language, condition_on_previous_text=condition, **PARAMS)
    segments, words, raw = [], [], []
    for s in segs_iter:
        raw.append(s.text)
        segments.append(
            {
                "start": round(s.start, 3),
                "end": round(s.end, 3),
                "text": s.text.strip(),
                "avg_logprob": round(s.avg_logprob, 4),
                "no_speech_prob": round(s.no_speech_prob, 4),
            }
        )
        words.extend({"start": round(w.start, 3), "end": round(w.end, 3), "word": w.word, "probability": round(w.probability, 4)} for w in s.words or ())
        reason = "transcribing" if attempt == 0 else "transcribing (retry)"
        out.send(("progress", (s.end / duration if duration else 0.0, reason)))
    return segments, words, "".join(raw).strip(), info


def _child(path: str, language: str | None, out) -> None:
    try:
        from faster_whisper import WhisperModel, decode_audio

        out.send(("progress", (0.0, "decoding audio")))
        try:
            audio = decode_audio(path, sampling_rate=SAMPLE_RATE)
        except Exception as e:  # noqa: BLE001 - av raises many kinds; any of them means the file is unreadable
            out.send(("error", (f"cannot decode the audio: {e}", False)))
            return
        duration = len(audio) / SAMPLE_RATE
        loud_s = _loud_seconds(audio)
        if duration < 0.1:
            out.send(("error", ("the audio is empty", False)))
            return

        out.send(("progress", (0.0, "loading model")))
        t0 = time.monotonic()
        model = WhisperModel(MODEL, **COMPUTE)
        load_s = time.monotonic() - t0

        t1 = time.monotonic()
        retry_reason = None
        for attempt, condition in enumerate((True, False)):
            segments, words, text, info = _pass(model, audio, duration, language, condition, out, attempt)
            problem = problem_with(segments, loud_s)
            if not problem:
                break
            if attempt == 0:
                retry_reason = problem
                out.send(("progress", (0.0, "retrying")))
        run_s = time.monotonic() - t1

        out.send(
            (
                "result",
                {
                    "language": info.language,
                    "durationMs": round(duration * 1000),
                    "text": text,
                    "segments": segments,
                    "words": words,
                    "engine": "faster-whisper",
                    "model": MODEL,
                    "params": {
                        **PARAMS,
                        **COMPUTE,
                        "language": language,
                        "condition_on_previous_text": condition,
                        "language_probability": round(info.language_probability, 4),
                        "retry_reason": retry_reason,
                        "unresolved": problem,
                        "load_s": round(load_s, 2),
                        "transcribe_s": round(run_s, 2),
                    },
                    "rtf": round(run_s / duration, 4) if duration else None,
                },
            )
        )
    except Exception as e:  # noqa: BLE001 - CUDA OOM, model download: worth another attempt
        out.send(("error", (f"{type(e).__name__}: {e}", True)))


# ── the parent ──────────────────────────────────────────────────────


def transcribe(path: Path, language: str | None, tick: Callable[[float, str], bool], on_start: Callable[[int], None] | None = None) -> dict:
    """Runs the child and returns the job result. Raises Stopped when tick() says stop, TranscribeError on failure."""
    ctx = mp.get_context("spawn")
    inbox, out = ctx.Pipe(duplex=False)
    child = ctx.Process(target=_child, args=(str(path), language, out), name="transcribe", daemon=True)
    child.start()
    out.close()  # the child holds the only write end now: EOF means it died
    if on_start and child.pid:
        on_start(child.pid)
    progress, reason = 0.0, "starting"
    finished = False
    try:
        while True:
            if inbox.poll(1):
                try:
                    kind, value = inbox.recv()
                except EOFError:
                    child.join(5)
                    raise TranscribeError(f"the transcriber died (exit code {child.exitcode})", retry=True) from None
                if kind == "progress":
                    progress, reason = value
                elif kind == "result":
                    finished = True
                    return value
                elif kind == "error":
                    finished = True
                    raise TranscribeError(*value)
            if not tick(progress, reason):
                raise Stopped()
    finally:
        # A child that reported has nothing left but freeing CUDA: let it exit by itself. Anything else is a kill.
        child.join(15 if finished else 0)
        if child.is_alive():
            child.kill()
            child.join(10)
        inbox.close()
