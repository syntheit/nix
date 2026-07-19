#!/usr/bin/env python3
# osk-harness.py — headless ibus-typing-booster regression harness for fajita.
# See ~/fajita-notes/keyboard-prediction.md §"harness usage" for usage and
# deploy runbook (engine python-env discovery, mandatory flags, battery cases).
# ALWAYS run with: --no-surround --reset-after-commit 30
"""Headless typing harness for ibus-typing-booster on fajita.

Emulates an application + OSK exactly the way GNOME Shell does:
- keys go in via process_key_event_async(keyval, 0, 0) — press, then a
  release IF the press was consumed (mirrors inputMethod.js handleVirtualKey);
  if the press was NOT consumed, the char is appended directly (mirrors the
  shell's raw-keyval fallback, which on a real phone types the char).
- commit-text / delete-surrounding-text signals mutate a local text buffer
  (the "screen").
- surrounding-text is pushed back to the engine, optionally LAGGED by N
  pending events to reproduce the real client's stale view.

Usage: osk-harness.py [--lag N] [--osk-cap] "teh holaa mañana "
Prints a per-event trace and the final screen text.
"""
import argparse
import sys

import gi
gi.require_version('IBus', '1.0')
from gi.repository import IBus, GLib  # noqa: E402


class Harness:
    def __init__(self, lag, osk_cap, shell_caps=False, no_surround=False,
                 reset_after_commit=0):
        self.lag = lag
        self.reset_after_commit = reset_after_commit
        self.text = ''
        self.preedit = ''
        self.preedit_ever = []
        self.candidates_log = []
        self.pending_surrounding = []
        self.loop = GLib.MainLoop()
        self.bus = IBus.Bus()
        if not self.bus.is_connected():
            sys.exit('cannot connect to ibus bus')
        self.ctx = self.bus.create_input_context('osk-harness')
        if shell_caps:
            caps = IBus.Capabilite.PREEDIT_TEXT | IBus.Capabilite.FOCUS
            if not no_surround:
                caps |= IBus.Capabilite.SURROUNDING_TEXT
            if hasattr(IBus.Capabilite, 'OSK'):
                caps |= IBus.Capabilite.OSK
        else:
            caps = (IBus.Capabilite.PREEDIT_TEXT
                    | IBus.Capabilite.FOCUS
                    | IBus.Capabilite.SURROUNDING_TEXT
                    | IBus.Capabilite.LOOKUP_TABLE
                    | IBus.Capabilite.AUXILIARY_TEXT)
            if osk_cap and hasattr(IBus.Capabilite, 'OSK'):
                caps |= IBus.Capabilite.OSK
        self.no_surround = no_surround
        self.ctx.set_capabilities(caps)
        self.ctx.connect('commit-text', self.on_commit)
        self.ctx.connect('delete-surrounding-text', self.on_delete)
        self.ctx.connect('update-preedit-text', self.on_preedit)
        self.ctx.connect('update-lookup-table', self.on_lookup)
        ge = self.bus.get_global_engine()
        self.prev_engine = ge.get_name() if ge else None
        print(f'global engine before: {self.prev_engine}')
        self.bus.set_global_engine('typing-booster')
        self.ctx.focus_in()
        self.push_surrounding(force=True)

    # --- app model ----------------------------------------------------------
    def on_commit(self, _ctx, ibus_text):
        s = ibus_text.get_text()
        self.text += s
        print(f'  COMMIT {s!r:12} screen={self.text!r}')
        self.queue_surrounding()
        if self.reset_after_commit:
            # mimic mutter/gnome-shell: the client resets the input context
            # shortly after applying a commit (inputMethod.js vfunc_reset)
            def do_reset():
                print('  CLIENT-RESET (mimicking mutter post-commit reset)')
                self.ctx.reset()
                return GLib.SOURCE_REMOVE
            GLib.timeout_add(self.reset_after_commit, do_reset)

    def on_delete(self, _ctx, offset, nchars):
        # offset is relative to cursor (cursor at end of self.text)
        start = len(self.text) + offset
        end = start + nchars
        removed = self.text[start:end]
        self.text = self.text[:start] + self.text[end:]
        print(f'  DELETE offset={offset} n={nchars} removed={removed!r} '
              f'screen={self.text!r}')
        self.queue_surrounding()

    def on_preedit(self, _ctx, ibus_text, _cursor, _visible):
        self.preedit = ibus_text.get_text()
        if self.preedit:
            self.preedit_ever.append(self.preedit)
            print(f'  PREEDIT {self.preedit!r}   <-- should never happen')

    def on_lookup(self, _ctx, table, _visible):
        cands = []
        for i in range(min(table.get_number_of_candidates(), 5)):
            cands.append(table.get_candidate(i).get_text())
        if cands:
            self.candidates_log.append(cands)
            print(f'  CANDIDATES {cands}')

    # --- surrounding text with optional lag ---------------------------------
    def queue_surrounding(self):
        self.pending_surrounding.append(self.text)
        while len(self.pending_surrounding) > self.lag:
            state = self.pending_surrounding.pop(0)
            self.send_surrounding(state)

    def push_surrounding(self, force=False):
        if force:
            while self.pending_surrounding:
                self.send_surrounding(self.pending_surrounding.pop(0))
            self.send_surrounding(self.text)

    def send_surrounding(self, state):
        if self.no_surround:
            return
        t = IBus.Text.new_from_string(state)
        self.ctx.set_surrounding_text(t, len(state), len(state))

    # --- key input ----------------------------------------------------------
    def press(self, char):
        keyval = IBus.unicode_to_keyval(char)
        consumed = {'v': None}

        def on_press(ctx, res):
            try:
                consumed['v'] = ctx.process_key_event_async_finish(res)
            except GLib.Error as e:
                print(f'  press error: {e}')
                consumed['v'] = False
            self.loop.quit()

        self.ctx.process_key_event_async(keyval, 0, 0, -1, None, on_press)
        self.loop.run()
        if consumed['v']:
            # mirror handleVirtualKey: send release, ignore result
            def on_release(ctx, res):
                try:
                    ctx.process_key_event_async_finish(res)
                except GLib.Error:
                    pass
                self.loop.quit()
            self.ctx.process_key_event_async(
                keyval, 0, IBus.ModifierType.RELEASE_MASK, -1, None,
                on_release)
            self.loop.run()
        else:
            # shell fallback: raw keyval → app receives the char
            self.text += char
            print(f'  FALLBACK {char!r}  screen={self.text!r}')
            self.queue_surrounding()
        return consumed['v']

    def settle(self, ms):
        GLib.timeout_add(ms, self.loop.quit)
        self.loop.run()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lag', type=int, default=0,
                    help='surrounding-text updates held back N events')
    ap.add_argument('--osk-cap', action='store_true',
                    help='advertise IBus.Capabilite.OSK')
    ap.add_argument('--shell-caps', action='store_true')
    ap.add_argument('--no-surround', action='store_true')
    ap.add_argument('--reset-after-commit', type=int, default=0,
                    metavar='MS', help='send ctx.reset() N ms after each '
                    'commit-text, mimicking mutter real-client behavior')
    ap.add_argument('text')
    args = ap.parse_args()

    h = Harness(args.lag, args.osk_cap, args.shell_caps, args.no_surround,
                args.reset_after_commit)
    h.settle(400)  # engine focus/context settle
    for ch in args.text:
        print(f'KEY {ch!r} (consumed={h.press(ch)})')
        h.settle(120)
    h.settle(600)
    h.push_surrounding(force=True)
    h.settle(200)
    print(f'\nFINAL SCREEN: {h.text!r}')
    print(f'preedit ever shown: {h.preedit_ever or "no"}')
    h.ctx.focus_out()
    if h.prev_engine and h.prev_engine != 'typing-booster':
        h.bus.set_global_engine(h.prev_engine)
        print(f'restored global engine: {h.prev_engine}')


if __name__ == '__main__':
    main()
