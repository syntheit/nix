# Upgrade rehearsal on a copy of the real data

This is step 1 of the vista plan: the tested restore. It decrypts the
pre-upgrade backup into memory that only this run can see. It then runs the
next steps against that copy: patched NanoMDM v0.9 on the real store, a
rollback to v0.6, and the new Deus's database migrations. It prints one
PASS/FAIL line per check and wipes everything.

The live services, their data, the Macs and Apple are never touched. The run
cannot reach them over the network, and it cannot see their files or sockets.

## What it proves

| Check | What PASS means |
| --- | --- |
| `isolation` | The sandbox has no network interface except loopback. Connects to vista's NanoMDM (10.100.0.4:9990), the Deus webhook (10.100.0.1:8086), an Apple address and 1.1.1.1 all fail. No host path except `/nix/store` is visible. No capabilities are left. |
| `decrypt` | age decrypts the backup with your identity, and the archive extracts cleanly. This is the tested restore. |
| `layout` | The archive holds exactly one NanoMDM store and one `deus.db`, and the rest of what restoring NanoMDM needs: exactly one `scep/` directory whose `ca.pem` and `ca.key` are non-empty files, exactly one `nanodep/` directory with at least one non-empty file, and at least one push certificate (a `<topic>.pem` beside its `<topic>.key` in the store, both non-empty). All of this is checked by stat only; no content is read or printed. Without the store or `deus.db` the run stops here. A missing SCEP, NanoDEP or push-certificate piece fails `layout`, and the other checks still run. |
| `enrollments` | The number of device enrollments (directories with `Authenticate.plist`) equals the expected count. That count is the number of rows in the baseline, 535. |
| `bootstraptokens` | The number of `BootstrapToken.dat` files equals the expected count, and, whenever a baseline is given (also with `--expected-count`), no token the baseline lists is missing from the backup. It compares them with the baseline by ID and size and reports how many are missing, new or resized. A missing token fails the check even when the counts agree, and its enrollment ID is printed. |
| `v09.start`, `v09.version` | The exact patched v0.9 binary that step 3 would run starts on the store copy with `-storage file -storage-options enable_deprecated=1`. Its `/version` begins with `0.9.0-patched-3c52ba4a031c`. Those storage flags are the ones step 3's entrypoint passes, and v0.6's (`-storage file`, no `-storage-options`, which v0.6 refuses) are the ones today's entrypoint passes: the build checks both against the entrypoints, and the run checks again and fails `v09.start` or `v06.start` on a mismatch without starting that server. |
| `v09.read` | v0.9's own storage code reads every enrollment. That covers Authenticate, push info, bootstrap tokens, queued commands and the push certificate. There are no read errors. |
| `v09.unchanged` | After v0.9 has run, the store's stat manifest is identical to the one taken before. The manifest records path, type, mode, size and mtime, never contents. |
| `v06.*` | The same checks for the v0.6.0 binary that vista runs today. It runs without `enable_deprecated` on the same copy, after v0.9 has opened it. This is the rollback. |
| `deus.migrate` | The new Deus's `deus-server -migrate-only -state-dir /work/deus-new` upgrades a copy of the real `deus.db` on the tmpfs, and its report names that copy and says it migrated it. The line gives the duration, the exit code and the table count before and after. FAIL, with nothing run on the copy, when the copy lacks any table that the old Deus's own `store.Open` creates (the build lists them) or has no rows in `heartbeats`: an empty database, which a mistyped `.backup` source makes, would otherwise pass all three Deus checks. FAIL when the binary is missing or has no `-migrate-only`, when it exits 1 (the open or the upgrade failed), or when its report does not name the copy or says it created a new database. |
| `deus.integrity` | `deus-server -migrate-only` exited 0: its own `integrity_check` says only `ok` and its `foreign_key_check` has no rows. The harness's `sqlite3` then agrees on the same copy. Exit 2 (upgraded, but a check found a problem) is a FAIL here. |
| `deus.rollback` | The Deus that vista runs today opens the migrated copy. It is also run on the untouched copy as a control. PASS means step 2 has a code-only rollback. FAIL, without running either, when the old Deus has the new one's revision or version. |

## What it does not prove

- **Live traffic.** No Mac checks in, and nothing is pushed, enqueued or sent
  to a webhook. So this rehearsal cannot show that v0.9 handles real
  check-ins, or that v0.6 can read files v0.9 *writes* during real traffic.
  (For example, in v0.9 an accepted Authenticate clears the bootstrap
  token.) It shows that v0.9 opens the real store without changing it, and
  that v0.6 still reads the store afterwards.
- **Server-level enumeration.** NanoMDM v0.6 and v0.9 have no read-only API
  that lists enrollments. Their routes are `/mdm`, `/version` and, with an
  API key, pushcert upload, push, enqueue, escrowkeyunlock and migration,
  and every one of those writes or calls Apple. So the servers run with no
  API key at all, and the reads go through a small probe (`probe/main.go`).
  The probe is compiled inside each version's own source tree and calls only
  that version's storage read methods.
- **Deus beyond its migrations.** `deus-server -migrate-only` (Deus
  `c26640d`) runs right after flag parsing, before the logger, any token or
  secret, and any listener or socket. It opens `<state-dir>/deus.db` with
  the same `store.Open` the service uses, reports, and exits. So the rest of
  `deus-server`'s startup, its loops and its retention pruning are not
  exercised. The old Deus that vista runs has no `-migrate-only`, so the
  rollback check opens the migrated copy with its
  `deus-rack-import -dry-run`, which calls that version's `store.Open`. It
  runs with an empty workbook and an empty host list, so it reads and
  writes nothing else.
- **Anything the other steps change.** That includes container images and
  the Docker or nspawn wiring, file ownership (the copy is extracted without
  owners), the UID 999→3999 move, the credential switch and `-dm`.
- **That the backup is current.** Anything written after the backup was taken
  is not in it.

## Secrets and side effects: how the harness keeps them contained

- **The Nix store holds only code.** It is world-readable, so no backup,
  key, token or data path is ever built into it. The harness refuses a
  backup that sits in `/nix/store`.
- **Plaintext lives only in a private tmpfs.** The harness creates a fresh
  tmpfs, root-only (0700) and `noswap`, inside a mount namespace of its
  own (and a network namespace of its own), so no other process on vista
  can see it. Before it mounts anything it compares both namespaces with
  pid 1's and refuses to go on if either is the same, so even a hand-typed
  `--stage ns` cannot mount the tmpfs where the services live. It refuses
  to go on unless `/proc/self/mountinfo` shows exactly the tmpfs it just
  mounted, tagged with a random name. On every exit (success, failure,
  error, Ctrl-C or kill) it zeroes every file, deletes it, unmounts the
  tmpfs and removes the mountpoint, and only then prints a `WIPE:` line
  that says so. During that cleanup it ignores further Ctrl-C, TERM, HUP
  and SIGPIPE, so neither a second Ctrl-C nor a `tee` that has died can
  stop it. If the harness
  itself is killed with `kill -9`, the namespace dies with it and the kernel
  frees the tmpfs; only an empty directory in `/run` is left behind.
- **The identity is typed, never stored.** You paste it at a prompt with
  echo off. It is kept in shell variables and passed through pipes to
  `age --identity -`. It never goes into a file, a command line or the
  environment. Only the public recipient is printed.
- **No network.** Everything that touches the data runs in a bubblewrap
  sandbox. It has a network namespace whose only interface is loopback, no
  host filesystem except `/nix/store` read-only, and no capabilities. The
  first check proves this from inside the sandbox. Because `/run` and
  `/var` are not visible, host Unix sockets such as Docker's, systemd's
  and the nspawn containers' cannot be reached either.
- **Nothing secret is printed.** The output contains counts, sizes,
  durations, exit codes, version strings, the relative paths of the
  backup's parts, and PASS or FAIL. It never prints file contents or
  database rows. The one kind of enrollment ID it prints is that of a
  bootstrap token the baseline lists and the backup lacks: an ID the
  baseline file already holds, and never the token. The only SQL it runs reads table names
  and counts from `sqlite_master`, `SELECT count(*) FROM heartbeats`, and
  two `PRAGMA` checks, so no row, `admin_password` or token column is ever
  read. `deus-server -migrate-only` runs the same kind of counts and
  checks. Its report can name a table and a row id, so it stays in the
  wiped log, and only its counts and exit code are printed. `--show-errors` is opt-in. It prints a failing tool's own
  last error lines, which can name a file, a table or a constraint.
- **Production comes first.** The run has an OOM score of 1000, so the
  kernel kills it before any service. It runs at lower CPU and I/O
  priority. As root it runs inside a transient systemd scope capped at
  `--memory-max` (default 14G), with swap disabled.

## Before you start

- The encrypted backup from step 0. It is an age-encrypted tar, either plain
  or compressed with gzip, xz or zstd. It must hold the NanoMDM file store
  (`…/mdm/nanomdm/`) and `deus.db` (with its `-wal` and `-shm` if they were
  captured), with the push certificate in the store. It must also hold the
  `scep/` directory with `ca.pem` and `ca.key`, and the `nanodep/`
  directory; `layout` fails without them. If the finder cannot pick out the
  store or `deus.db`, name them with `--nanomdm-path` or `--deus-db-path`. Do not
  make the backup with `bsdtar --zstd -cf -`: libarchive 3.8.9 writes a
  truncated stream that way. If the backup was made like that, the
  `decrypt` check will fail.
- The age identity (`AGE-SECRET-KEY-1…`) that the backup was encrypted to.
- The baseline: `/home/daniel/m1-5fro/bstoken-baseline-20260920.tsv`
  (535 rows).
- Free memory of about twice the size of `deus.db`, plus the NanoMDM
  store. The harness prints how much is available when it starts.

## Step 1: build (your normal user, no sudo, about 5–15 minutes the first time)

```sh
/home/daniel/Projects/malli-nix-macos-updates/tools/rehearsal/build.sh --old-deus-rev 410a695
```

`410a695` is the Deus deployed on vista today (0.57.19). Name it: without
`--old-deus-rev`, the build takes the `deus` revision locked in
`/home/daniel/nix/flake.lock`, and that lock moves to the new Deus as soon
as step 2 is prepared.

The build uses only committed trees, never uncommitted work:

- the harness from this repository's `HEAD`;
- NanoMDM v0.6 from the binary that the nanomdm container entrypoint in
  vista's configuration runs. It is byte-identical to the one in the
  running image;
- NanoMDM v0.9 from the same configuration with the step-3 pin set. It is
  fed from the new Deus's vendored `third_party/nanomdm`, and its tree hash
  is checked;
- the new Deus from the committed head of `feature/macos-updates`. Its
  `deus-server` must have `-migrate-only` (Deus `c26640d`, in 0.58.0). The
  build stops with an error on a Deus without it, and the run checks again;
- the old Deus from `--old-deus-rev` in `/home/daniel/Projects/malli-deus`
  (a short revision is fine). It is the rollback target, and its schema is
  the one a real `deus.db` must have. An old Deus with the new one's
  revision would make `deus.rollback` test the new Deus against itself, so
  `build.sh` refuses the same revision, the build refuses the same version,
  and the run fails `deus.rollback` on either. Both versions are printed at
  the top of the report and again in the summary.

If step 2 will deploy a different Deus revision, pass
`--new-deus-rev <sha>` and build again. `build.sh` prints the store path of
the harness and leaves GC roots in `~/.cache/malli-rehearsal/`.

## Step 2: run (as root, a few minutes)

Use the `/nix/store/…` path that `build.sh` printed:

```sh
sudo /nix/store/…-malli-rehearse/bin/malli-rehearse \
  --backup /path/to/backup.tar.zst.age \
  --baseline /home/daniel/m1-5fro/bstoken-baseline-20260920.tsv \
  2>&1 | tee ~/rehearsal-report.txt; echo "malli-rehearse exit: ${pipestatus[1]}"
```

That line is for zsh, your shell. A pipeline's own status is `tee`'s,
which is 0 even when the rehearsal failed, so `$?` says nothing here.
zsh keeps each command's status in `pipestatus`, counted from 1, and
`${pipestatus[1]}` is `malli-rehearse`'s. (In bash it is
`${PIPESTATUS[0]}`. Either shell can instead `setopt pipefail` or
`set -o pipefail` first, and then `$?` is non-zero when the harness fails.)

Run it with `sudo` from your own shell, as above. Never run it from a
root shell (`sudo -i`, `sudo su`): anything you paste that the harness
does not read goes to the shell that started it, and a root shell's
history is one more place a key could be written.

The only thing you type is the identity. At
`Paste the age identity (the AGE-SECRET-KEY-1... line, or the whole key file), then Enter. Nothing is echoed:`,
paste the `AGE-SECRET-KEY-1…` line, or the whole key file as `age-keygen`
wrote it, and press Enter. Blank lines and `#` lines (`# created:`,
`# public key:`) are skipped; the first other line must be the key, within
the first 8 lines. Whatever else was pasted with it is read and dropped,
so nothing is left for your shell. If you know the backup's recipient, add
`--recipient age1…` and the harness will refuse any other identity before
it decrypts anything.

The report file contains no secret, so it is safe to keep. Its last lines
are the summary (ending in `CHECKS: PASS` or `CHECKS: FAIL`), the `WIPE:`
line, and then the harness's own verdict, always the very last line:
`RESULT: PASS (every check passed)` or `RESULT: FAIL (exit N: …)`. Read
that line; it is printed on every way out, including a refusal before
anything is mounted, an unexpected error (the summary then says in which
phase the run stopped), a Ctrl-C, or a `tee` that has died. Only
`kill -9` leaves no `RESULT:` line, and then the exit status is 137. The
exit status is 0 only when every check passes.

**How long plaintext exists, and where.** Decrypted data exists only from
the start of the `decrypt` phase until the `WIPE:` line, which is the rest
of the run (minutes). It exists only in the private tmpfs, in RAM that is
never swapped and that no other process can see, and in the memory of the
sandboxed processes that read it. The identity is held in memory from the
moment you press Enter until decryption finishes (seconds), and those
variables are cleared then.

## If a check fails

- `decrypt`: the wrong identity, or a damaged or truncated backup. Do not go
  on to step 2 or 3. Make a new backup first.
- `enrollments` or `bootstraptokens`: read the counts on the line. "new"
  against the baseline means Macs enrolled since 2026-09-20. "missing"
  always fails `bootstraptokens`, even when the counts agree, and the lines
  above it list each missing enrollment ID: that Mac was removed since
  2026-09-20, or the backup is incomplete. Find out which before step 3.
- `v09.*` or `v06.*`: do not start step 3. The step-3 rollback cannot be
  trusted.
- `deus.migrate` or `deus.integrity`: do not start step 2. The new Deus
  applies its whole upgrade in one transaction, so a failed upgrade should
  leave the file as it was. The table counts before and after on the
  `deus.migrate` line show whether it did. A `deus.migrate` that says the
  flag is missing means the harness was built from the wrong Deus: build
  again with `--new-deus-rev`.
- `deus.rollback`: step 2 is one-way. Rolling it back means restoring
  `deus.db` from the backup.

To see why a tool failed, run again with `--show-errors`.

## Options

`--expected-count N` (instead of the baseline's row count),
`--recipient age1…`, `--nanomdm-path REL`, `--deus-db-path REL`,
`--tmpfs-size 12g`, `--memory-max 14G`, `--work-parent /run`,
`--show-errors`. `malli-rehearse --help` lists them.

## Self-test (synthetic data only, no sudo)

```sh
tools/rehearsal/build.sh --old-deus-rev 410a695 --selftest
~/.cache/malli-rehearsal/selftest/bin/malli-rehearsal-selftest /tmp/rehearsal-selftest
```

It builds made-up data: a NanoMDM store, a push certificate, and a
`deus.db` created by the old Deus, all encrypted to a throwaway key. It then
runs itself as pid 1 of a pid namespace of its own, as root of an
unprivileged user namespace, so the harness can compare its namespaces with
pid 1's as it does on vista. It runs the harness in these cases:

- good data, with the whole key file on stdin and pasted at the hidden
  prompt: every check passes;
- a key file whose first line that is not blank or a comment is not the
  key: refused before anything is decrypted;
- a wrong count;
- a corrupt archive;
- a v0.9 that leaves the store unreadable to v0.6;
- a failing migration (`deus-server -migrate-only` exits 1);
- a migration that applies but leaves a dangling foreign key (exit 2);
- one Mac lost since the baseline and one new, so the counts agree, with
  and without `--expected-count`;
- a backup without the `scep/` directory, without `scep/ca.key`, with an
  empty `nanodep/`, or without the push certificate;
- an empty `deus.db`, as a mistyped `.backup` source makes, and one with
  the old schema but no `heartbeats` rows;
- a new Deus whose `deus-server` has no `-migrate-only`;
- a harness whose old Deus is the new one;
- a step-3 entrypoint that no longer passes `-storage-options
  enable_deprecated=1`, while the harness would;
- `--stage ns` typed by hand in pid 1's mount namespace, and in a private
  mount namespace that shares pid 1's network: both refuse before mounting
  anything;
- a Ctrl-C mid-run, and a `kill -9` mid-run;
- the reader of the output killed (as a dead `| tee` would be) and then a
  Ctrl-C, and a second Ctrl-C to the whole process group while the cleanup
  waits for the sandbox: both must still wipe;
- an unexpected error inside the sandbox (a `cp` that fails, as on a full
  tmpfs) and one outside it before the tmpfs exists: both must still end
  with `RESULT: FAIL`, the first after the summary and the wipe.

Every case must end with a complete wipe, with a last line of
`RESULT: PASS` exactly when the exit status is 0 and `RESULT: FAIL`
otherwise, and with none of the planted secret markers in the output. The markers are the identity, bootstrap
tokens, passwords, enrollment IDs and host names.
