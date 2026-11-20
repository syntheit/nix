"""Pull worker for construct's job queue (memos.transcribe, memos.title, memos.tag)."""


class Stopped(Exception):
    """The job was cancelled or taken back (a progress call answered cancel or hold): drop it."""
