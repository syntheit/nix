#!/usr/bin/env python3
"""Convert an AOSP "combined" wordlist into a compact read-only SQLite frequency DB.

This is used by a forked ibus-typing-booster keyboard engine on a Linux phone.
The engine needs sub-millisecond word lookups without loading a big flat file into
RAM on every keystroke, so we ship a single SQLite file with a b-tree PRIMARY KEY
index on the word column and open it read-only (PRAGMA query_only).

=== AOSP COMBINED FORMAT (plaintext UTF-8) ===
First line is a header, e.g.:
    dictionary=main:en_us,locale=en_US,description=English (US),date=...,version=54

Then repeating blocks, one unigram followed by zero or more bigram continuation
lines that belong to it:
    (1 leading space)  word=the,f=222,flags=,originalFreq=222
    (2 leading spaces) bigram=new,f=1
    (2 leading spaces) bigram=first,f=2
    (2 leading spaces) bigram=same,f=3
    (1 leading space)  word=to,f=215,flags=,originalFreq=208

Line kinds:
  * word=    -> a unigram. `f` is an integer 0..255 (AOSP log-scaled frequency,
               255 = max; it is NOT a linear count). `flags` may be empty or a
               colon-separated set (abbreviation, medical, nonword, offensive,
               possibly_offensive, hand-added, babytalk, drugs, australian, ...).
               `originalFreq` is ignored; we always use `f`.
  * bigram=  -> a continuation of the MOST RECENT preceding `word=` line. The
               preceding word is the PREVIOUS word; the bigram token is the NEXT
               word. IMPORTANT CAVEAT: for bigrams `f` is NOT a frequency, it is an
               ordinal RANK (1, 2, 3 = the top-3 most likely next words). We store
               it as `rank`, never as a frequency.
  * shortcut= -> skipped entirely (its `f` is non-numeric, e.g. f=whitelist).

Field parsing is order-independent: we split a line on commas and find the
key=value pair whose key is exactly `f` (and `flags`), rather than assuming a
fixed column order. The leading token's value is everything after the first `=`
in the first field, so tokens containing `=` are handled. Apostrophes (don't,
I'll) and accented unicode (tenés) pass through unchanged.
"""

import argparse
import gzip
import os
import re
import sqlite3
import sys
import time

# Batch size for executemany inserts. Large enough to amortize call overhead,
# small enough to keep parameter lists reasonable.
BATCH_SIZE = 20000

# Flags (colon-separated members) that mark a word as offensive.
OFFENSIVE_FLAGS = frozenset(("offensive", "possibly_offensive"))


def open_input(path):
    """Open the input for streaming text reads, transparently handling .gz.

    Returns a file object yielding str lines (utf-8). Never reads the whole
    file into memory; callers must iterate line by line.
    """
    if path.endswith(".gz"):
        return gzip.open(path, mode="rt", encoding="utf-8")
    return open(path, mode="rt", encoding="utf-8")


def parse_fields(body):
    """Parse a comma-separated `key=value` body into a dict.

    `body` is the line with its leading whitespace and trailing newline already
    stripped, e.g. "word=the,f=222,flags=,originalFreq=222".

    The leading token (word=/bigram=/etc.) keeps everything after its first `=`
    as the value, so a token containing `=` survives. Later fields are split on
    the first `=` as well. Fields without any `=` are ignored.
    """
    fields = {}
    for part in body.split(","):
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        # Keep the FIRST occurrence of a key; AOSP never repeats keys within a
        # line, but this is deterministic if it ever did.
        if key not in fields:
            fields[key] = value
    return fields


def build(args):
    """Stream the input, collect unigrams/bigrams, and write the SQLite DB."""
    start = time.time()

    input_basename = os.path.basename(args.input)

    # word -> (freq, flags). Max-freq dedupe and the min-freq/drop-offensive
    # filters are applied as we stream.
    unigrams = {}
    # (prev, word) -> min rank. Collected for every bigram regardless of whether
    # the endpoints pass unigram filters; survival is resolved after pruning.
    bigrams = {}

    # The most recent `word=` token seen, used as the "previous" word for any
    # following bigram lines. We track the RAW token even if that unigram was
    # filtered out, because bigram survival is decided against the FINAL set.
    current_prev = None

    source_header = None
    locale = ""
    malformed_lines = 0

    # A word/bigram line always starts with leading space(s); we distinguish the
    # two by counting them (1 = unigram, 2 = bigram continuation).
    leading_ws = re.compile(r"^( +)")

    with open_input(args.input) as handle:
        for lineno, raw in enumerate(handle):
            line = raw.rstrip("\n")

            # First non-empty line is the header.
            if source_header is None:
                source_header = line
                header_fields = parse_fields(line)
                locale = header_fields.get("locale", "")
                continue

            if not line.strip():
                continue

            match = leading_ws.match(line)
            indent = len(match.group(1)) if match else 0
            body = line.strip()

            try:
                if body.startswith("word="):
                    fields = parse_fields(body)
                    token = fields.get("word", "")
                    if token == "":
                        malformed_lines += 1
                        continue

                    # This word becomes the "previous" for subsequent bigrams,
                    # regardless of whether it passes the filters below.
                    current_prev = token

                    if "f" not in fields:
                        malformed_lines += 1
                        continue
                    freq = int(fields["f"])
                    flags = fields.get("flags", "")

                    if args.drop_offensive:
                        flag_set = set(f for f in flags.split(":") if f)
                        if flag_set & OFFENSIVE_FLAGS:
                            continue

                    if freq < args.min_freq:
                        continue

                    # Duplicate word: keep the MAX freq (and its flags).
                    existing = unigrams.get(token)
                    if existing is None or freq > existing[0]:
                        unigrams[token] = (freq, flags)

                elif body.startswith("bigram="):
                    # A bigram continuation with no preceding word= is malformed.
                    if current_prev is None:
                        malformed_lines += 1
                        continue
                    fields = parse_fields(body)
                    target = fields.get("bigram", "")
                    if target == "" or "f" not in fields:
                        malformed_lines += 1
                        continue
                    rank = int(fields["f"])
                    key = (current_prev, target)
                    # Duplicate (prev, word): keep the MIN rank (best position).
                    existing_rank = bigrams.get(key)
                    if existing_rank is None or rank < existing_rank:
                        bigrams[key] = rank

                elif body.startswith("shortcut="):
                    # Shortcut lines have a non-numeric f (e.g. f=whitelist).
                    # They are not vocabulary; skip entirely.
                    continue

                else:
                    # Unknown line kind (not header, word, bigram, or shortcut).
                    malformed_lines += 1

            except ValueError:
                # int() failed on a non-numeric f, or similar: don't crash.
                malformed_lines += 1
                continue

    # --- Finalize the unigram set (top-n pruning) ---------------------------
    # top_n <= 0 means keep all. Otherwise keep the N highest-frequency words,
    # breaking ties deterministically by word so repeated runs are identical.
    if args.top_n > 0 and len(unigrams) > args.top_n:
        ordered = sorted(
            unigrams.items(),
            key=lambda item: (-item[1][0], item[0]),
        )
        unigrams = dict(ordered[: args.top_n])

    surviving_words = set(unigrams.keys())

    # --- Bigram survival filter --------------------------------------------
    # A bigram is kept ONLY IF both its prev word and its target word survive in
    # the final unigram set. min-freq, drop-offensive and top-n pruning all shape
    # that set, so this guarantees the engine can never reference a word that is
    # absent from the unigrams table (no dangling lookups at runtime).
    surviving_bigrams = [
        (prev, word, rank)
        for (prev, word), rank in bigrams.items()
        if prev in surviving_words and word in surviving_words
    ]

    # --- Write the SQLite database -----------------------------------------
    write_db(
        args.output,
        unigrams=unigrams,
        bigrams=surviving_bigrams,
        source_header=source_header if source_header is not None else "",
        locale=locale,
        input_basename=input_basename,
        malformed_lines=malformed_lines,
    )

    elapsed = time.time() - start
    output_size = os.path.getsize(args.output)

    print("aosp-dict-harvest convert.py", file=sys.stderr)
    print("  input       : {}".format(args.input), file=sys.stderr)
    print("  locale      : {}".format(locale or "(unknown)"), file=sys.stderr)
    print("  unigrams    : {}".format(len(unigrams)), file=sys.stderr)
    print("  bigrams     : {}".format(len(surviving_bigrams)), file=sys.stderr)
    if malformed_lines:
        print("  malformed   : {}".format(malformed_lines), file=sys.stderr)
    print("  elapsed     : {:.2f} s".format(elapsed), file=sys.stderr)
    print("  output      : {} ({} bytes)".format(args.output, output_size),
          file=sys.stderr)


def remove_db_and_sidecars(path):
    """Delete the DB file and any leftover WAL/SHM/journal sidecars for a fresh build."""
    for suffix in ("", "-wal", "-shm", "-journal"):
        candidate = path + suffix
        if os.path.exists(candidate):
            os.remove(candidate)


def write_db(path, unigrams, bigrams, source_header, locale,
             input_basename, malformed_lines):
    """Create the SQLite schema and bulk-insert all rows in one transaction.

    Why SQLite with a PRIMARY KEY index on `word` is the right storage here:
      * The keyboard engine needs <1ms lookups per keystroke. SQLite indexes the
        PRIMARY KEY as a b-tree, so a word lookup is a few page reads, not a
        linear scan of a flat file.
      * The DB is memory-mapped by SQLite, so we never load the whole ~15MB+
        wordlist into the Python process; only the pages actually touched are
        paged in by the OS.
      * It ships as a single self-contained file (easy to build once and copy to
        the phone) and can be opened strictly read-only via PRAGMA query_only,
        which also lets multiple readers share it safely.
    """
    remove_db_and_sidecars(path)

    conn = sqlite3.connect(path)
    try:
        cur = conn.cursor()

        # Build-time speed pragmas. journal_mode=OFF guarantees no -wal/-shm
        # sidecars are ever created; synchronous=OFF skips fsyncs (safe here
        # because the build is fully reproducible from the source wordlist).
        cur.execute("PRAGMA journal_mode=OFF")
        cur.execute("PRAGMA synchronous=OFF")

        cur.execute(
            "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)"
        )
        cur.execute(
            "CREATE TABLE unigrams ("
            "word TEXT PRIMARY KEY, freq INTEGER NOT NULL, flags TEXT)"
        )
        cur.execute(
            "CREATE TABLE bigrams ("
            "prev TEXT NOT NULL, word TEXT NOT NULL, rank INTEGER NOT NULL, "
            "PRIMARY KEY (prev, word))"
        )
        cur.execute("CREATE INDEX idx_bigrams_prev ON bigrams(prev)")

        # Single transaction around all inserts for speed.
        cur.execute("BEGIN")

        # Unigrams: parameterized executemany in batches.
        uni_rows = ((word, freq, flags) for word, (freq, flags) in unigrams.items())
        _executemany_batched(
            cur,
            "INSERT INTO unigrams (word, freq, flags) VALUES (?, ?, ?)",
            uni_rows,
        )

        # Bigrams: already a list of (prev, word, rank) tuples.
        _executemany_batched(
            cur,
            "INSERT INTO bigrams (prev, word, rank) VALUES (?, ?, ?)",
            iter(bigrams),
        )

        # Meta rows (all parameterized).
        meta_rows = [
            ("locale", locale),
            ("source_header", source_header),
            ("freq_scale", "0-255 AOSP log-scaled (255=max); NOT linear counts"),
            ("generated_by", "convert.py (aosp-dict-harvest)"),
            ("unigram_count", str(len(unigrams))),
            ("bigram_count", str(len(bigrams))),
            ("input_file", input_basename),
            ("malformed_lines", str(malformed_lines)),
        ]
        cur.executemany(
            "INSERT INTO meta (key, value) VALUES (?, ?)", meta_rows
        )

        conn.commit()

        # Let SQLite update internal stats for better query plans on the phone.
        cur.execute("PRAGMA optimize")
    finally:
        conn.close()


def _executemany_batched(cur, sql, rows, batch_size=BATCH_SIZE):
    """Run executemany over an iterable of rows in fixed-size batches."""
    batch = []
    for row in rows:
        batch.append(row)
        if len(batch) >= batch_size:
            cur.executemany(sql, batch)
            batch.clear()
    if batch:
        cur.executemany(sql, batch)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert an AOSP combined wordlist into a compact read-only "
                    "SQLite frequency database.",
    )
    parser.add_argument(
        "--input", required=True,
        help="Path to the AOSP .combined wordlist (transparently gunzipped if "
             "the name ends in .gz).",
    )
    parser.add_argument(
        "--output", required=True,
        help="Path for the SQLite database to create (rebuilt fresh each run).",
    )
    parser.add_argument(
        "--drop-offensive", action="store_true",
        help="Skip unigrams flagged offensive or possibly_offensive "
             "(default: keep everything).",
    )
    parser.add_argument(
        "--min-freq", type=int, default=0,
        help="Skip unigrams with f < N (AOSP 0-255 log scale). Default 0.",
    )
    parser.add_argument(
        "--top-n", type=int, default=0,
        help="Keep only the top-N unigrams by frequency (0 = keep all).",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    build(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
