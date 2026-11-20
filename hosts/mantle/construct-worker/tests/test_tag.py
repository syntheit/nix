"""memos.tag offline: canned Ollama answers, no model. Run: python3 -m unittest discover -s tests"""

import json
import unittest

from construct_worker import tag

VOCAB = [{"name": n, "hint": None} for n in ("Health", "Finance", "Plan", "Construct", "Idea", "Journal")]


class Resp:
    def __init__(self, content: str, status: int = 200):
        self.status_code = status
        self.text = content
        self._content = content

    def json(self):
        return {"message": {"content": self._content}}


class Http:
    """Answers chat calls from a queue; records every request."""

    def __init__(self, answers):
        self.answers = list(answers)
        self.calls = []

    def post(self, url, json=None, timeout=None):  # noqa: A002 - requests' own name
        self.calls.append((url, json))
        if url.endswith("/api/generate"):
            return Resp("")
        return Resp(self.answers.pop(0))


class Fake:
    def __init__(self, answers):
        self.url = "http://ollama"
        self.model = "qwen3:4b"
        self.http = Http(answers)


def seg(i, start_s, text="words " * 20):
    return {"start": start_s * 1000, "end": start_s * 1000 + 9000, "text": f"{i} {text}"}


def payload(n=12, every=10):
    return {"transcriptId": 1, "durationMs": n * every * 1000, "language": "en", "vocabulary": VOCAB, "segments": [seg(i, i * every) for i in range(n)]}


def chapters(*cs, continues=None):
    d = {"chapters": [{"start_line": line, "about": f"about {title}", "title": title} for line, title in cs]}
    if continues is not None:
        d["continues"] = continues
    return json.dumps(d)


def tags(*ts, new=None):
    return json.dumps({"parts": [{"n": k, "tags": list(t)} for k, t in enumerate(ts, 1)], "new_tag": new})


tick = lambda p, why: True  # noqa: E731


class Windows(unittest.TestCase):
    def test_split_at_segments(self):
        segs = [{"text": "x" * 100} for _ in range(10)]
        self.assertEqual([list(r) for r in tag.windows(segs, 300)], [[0, 1], [2, 3], [4, 5], [6, 7], [8, 9]])
        self.assertEqual([list(r) for r in tag.windows([{"text": "x" * 1000}, {"text": "y"}], 300)], [[0], [1]])
        self.assertEqual(tag.windows([], 300), [])

    def test_most_chapters(self):
        self.assertEqual([tag.most_chapters(m) for m in (0.5, 2, 6, 9.4)], [1, 1, 2, 3])


class Merge(unittest.TestCase):
    def test_no_gaps_and_short_chapters_join(self):
        found = [{"startMs": 4000, "title": "A", "about": "a"}, {"startMs": 30_000, "title": "B", "about": "b"}, {"startMs": 150_000, "title": "C", "about": "c"}, {"startMs": 230_000, "title": "D", "about": "d"}]
        out = tag.merge(found, 240_000)
        # A (0-30 s) joins B; D (230-240 s) joins C.
        self.assertEqual([(c["title"], c["startMs"], c["endMs"]) for c in out], [("B", 0, 150_000), ("C", 150_000, 240_000)])
        self.assertEqual(out[0]["about"], "a b")
        self.assertEqual(tag.merge([{"startMs": 0, "title": "Only", "about": ""}], 20_000)[0]["endMs"], 20_000)


class Checks(unittest.TestCase):
    def test_chapters(self):
        self.assertEqual(tag.check_chapters(chapters((3, "first"), (5, '  "Second." ')), 6)["chapters"], [(0, "First", "about first"), (4, "Second", 'about "Second."')])
        for bad, why in ((("not json"), "no JSON"), (json.dumps({"chapters": []}), "no chapters"), (chapters((1, "a"), (1, "b")), "starts at line 1"), (chapters((1, "a"), (9, "b")), "of 6"), (chapters((1, "")), "no title")):
            with self.assertRaises(tag.Garbage) as e:
                tag.check_chapters(bad, 6)
            self.assertIn(why, str(e.exception))

    def test_tags(self):
        names = [v["name"] for v in VOCAB]
        self.assertEqual(tag.check_tags(tags(["health", "Health"], []), 2, names, False)["tags"], [["Health"], []])
        with self.assertRaises(tag.Garbage):
            tag.check_tags(tags(["Cycling"]), 1, names, False)
        self.assertEqual(tag.check_tags(tags(["Cycling", "Plan"]), 1, names, True)["tags"], [["Plan"]])
        with self.assertRaises(tag.Garbage):
            tag.check_tags(tags(["Plan"]), 2, names, True)

    def test_titles(self):
        self.assertEqual(tag.clean_title("[12:30] moving savings into bonds."), "Moving savings into bonds")
        self.assertLessEqual(len(tag.clean_title("word " * 40)), tag.TITLE_CHARS)


class MakeChapters(unittest.TestCase):
    def test_two_windows_merged_and_tagged(self):
        p = payload(n=12, every=30)  # 12 segments of ~130 characters, 30 s apart: two windows (0-6, 7-11) at 1000
        fake = Fake([chapters((1, "Saddle"), (4, "Bonds")), chapters((1, "Bonds again"), (3, "Clothes app"), continues=True), tags(["Health"], ["Finance", "Plan"], ["Construct", "Idea"], new="Cycling")])
        r = tag.make_chapters(p, fake, tick, max_chars=1000)
        self.assertIsNone(r.get("error"))
        self.assertEqual([(c["title"], c["startMs"], c["endMs"], c["tags"]) for c in r["chapters"]], [("Saddle", 0, 90_000, ["Health"]), ("Bonds", 90_000, 270_000, ["Finance", "Plan"]), ("Clothes app", 270_000, 360_000, ["Construct", "Idea"])])
        self.assertEqual(r["suggest"], "Cycling")
        chats = [j for u, j in fake.http.calls if u.endswith("/api/chat")]
        self.assertEqual(len(chats), 3)
        # The second window is told what the first ended with and asked whether it continues; tags are an enum.
        self.assertIn('"Bonds"', chats[1]["messages"][0]["content"])
        self.assertIn("continues", chats[1]["format"]["properties"])
        self.assertEqual(chats[2]["format"]["properties"]["parts"]["items"]["properties"]["tags"]["items"]["enum"], [v["name"] for v in VOCAB])
        # Unloaded at the end.
        self.assertEqual(fake.http.calls[-1][1]["keep_alive"], 0)

    def test_short_chapters_need_a_minute(self):
        fake = Fake([chapters((1, "A"), (2, "B"), (7, "C")), tags([], [])])
        r = tag.make_chapters(payload(n=12), fake, tick)
        # B starts at 10 s: A (0-10 s) joins it.
        self.assertEqual([(c["title"], c["startMs"]) for c in r["chapters"]], [("B", 0), ("C", 60_000)])

    def test_garbage_twice_is_an_error_result(self):
        fake = Fake(["nope", "still nope"])
        r = tag.make_chapters(payload(), fake, tick)
        self.assertEqual(r["chapters"], [])
        self.assertIn("unusable chapters twice", r["error"])
        self.assertEqual(fake.http.calls[-1][1]["keep_alive"], 0)

    def test_garbage_once_asks_again(self):
        fake = Fake(["{", chapters((1, "All")), tags(["Journal"], new="Journal")])
        r = tag.make_chapters(payload(), fake, tick)
        self.assertEqual([c["tags"] for c in r["chapters"]], [["Journal"]])
        self.assertIsNone(r["suggest"])  # a tag from the list is no suggestion
        temps = [j["options"]["temperature"] for u, j in fake.http.calls if u.endswith("/api/chat")]
        self.assertEqual(temps, [0.2, 0.5, 0.2])

    def test_no_text_no_model(self):
        fake = Fake([])
        self.assertEqual(tag.make_chapters({**payload(), "segments": [{"start": 0, "end": 1, "text": "  "}]}, fake, tick), {"chapters": [], "suggest": None})
        self.assertEqual(fake.http.calls, [])

    def test_ollama_error_is_retryable(self):
        class Down(Fake):
            pass

        fake = Down([])
        fake.http.post = lambda url, json=None, timeout=None: Resp("model not found", 404)
        with self.assertRaises(tag.TagError):
            tag.make_chapters(payload(), fake, tick)


if __name__ == "__main__":
    unittest.main()
