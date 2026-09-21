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
| `layout` | The archive holds exactly one NanoMDM store and one `deus.db`. It also reports SCEP and NanoDEP if they are present. |
| `enrollments` | The number of device enrollments (directories with `Authenticate.plist`) equals the expected count. That count is the number of rows in the baseline, 535. |
| `bootstraptokens` | The number of `BootstrapToken.dat` files equals the expected count. It also compares them with the baseline by ID and size and reports how many are missing, new or resized. |
| `v09.start`, `v09.version` | The exact patched v0.9 binary that step 3 would run starts on the store copy with `-storage file -storage-options enable_deprecated=1`. Its `/version` begins with `0.9.0-patched-3c52ba4a031c`. |
| `v09.read` | v0.9's own storage code reads every enrollment. That covers Authenticate, push info, bootstrap tokens, queued commands and the push certificate. There are no read errors. |
| `v09.unchanged` | After v0.9 has run, the store's stat manifest is identical to the one taken before. The manifest records path, type, mode, size and mtime, never contents. |
| `v06.*` | The same checks for the v0.6.0 binary that vista runs today. It runs without `enable_deprecated` on the same copy, after v0.9 has opened it. This is the rollback. |
| `deus.migrate` | The new Deus opens a copy of the real `deus.db` and applies its migrations. The line gives the duration and the table count before and after. |
| `deus.integrity` | After migration, `PRAGMA integrity_check` returns `ok` and `PRAGMA foreign_key_check` returns no rows. |
| `deus.rollback` | The Deus that vista runs today opens the migrated copy. It is also run on the untouched copy as a control. PASS means step 2 has a code-only rollback. |

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
- **Deus beyond its migrations.** Deus has no migrate-only command. The
  smallest existing entry point that runs the migrations is
  `deus-rack-import -dry-run`, which calls the same `store.Open` as
  `deus-server`. It runs with an empty workbook and an empty host list, so
  it reads and writes nothing else. `deus-server`'s startup, its loops and
  its retention pruning are not exercised. A `-migrate-only` flag is
  proposed below.
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
  own, so no other process on vista can see it. It refuses to go on unless
  `/proc/self/mountinfo` shows exactly the tmpfs it just mounted, tagged
  with a random name. On every exit (success, failure, error, Ctrl-C or
  kill) it zeroes every file, deletes it, unmounts the tmpfs and removes
  the mountpoint, and prints a `WIPE:` line that says so. If the harness
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
  backup's parts, and PASS or FAIL. It never prints file contents,
  enrollment IDs or database rows. The only SQL it runs is
  `SELECT count(*) FROM sqlite_master` and two `PRAGMA` checks, so no row,
  `admin_password` or token column is ever read. `--show-errors` is
  opt-in. It prints a failing tool's own last error lines, which can name a
  file, a table or a constraint.
- **Production comes first.** The run has an OOM score of 1000, so the
  kernel kills it before any service. It runs at lower CPU and I/O
  priority. As root it runs inside a transient systemd scope capped at
  `--memory-max` (default 14G), with swap disabled.

## Before you start

- The encrypted backup from step 0. It is an age-encrypted tar, either plain
  or compressed with gzip, xz or zstd. It must hold the NanoMDM file store
  (`…/mdm/nanomdm/`) and `deus.db` (with its `-wal` and `-shm` if they were
  captured). SCEP and NanoDEP directories are optional. If the finder cannot
  pick them out, name them with `--nanomdm-path` or `--deus-db-path`. Do not
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
/home/daniel/Projects/malli-nix-macos-updates/tools/rehearsal/build.sh
```

The build uses only committed trees, never uncommitted work:

- the harness from this repository's `HEAD`;
- NanoMDM v0.6 from the binary that the nanomdm container entrypoint in
  vista's configuration runs. It is byte-identical to the one in the
  running image;
- NanoMDM v0.9 from the same configuration with the step-3 pin set. It is
  fed from the new Deus's vendored `third_party/nanomdm`, and its tree hash
  is checked;
- the new Deus from the committed head of `feature/macos-updates`;
- the old Deus from the `deus` revision locked in `/home/daniel/nix/flake.lock`,
  which is what vista runs.

If step 2 will deploy a different Deus revision, pass
`--new-deus-rev <sha>` and build again. `build.sh` prints the store path of
the harness and leaves GC roots in `~/.cache/malli-rehearsal/`.

## Step 2: run (as root, a few minutes)

Use the `/nix/store/…` path that `build.sh` printed:

```sh
sudo /nix/store/…-malli-rehearse/bin/malli-rehearse \
  --backup /path/to/backup.tar.zst.age \
  --baseline /home/daniel/m1-5fro/bstoken-baseline-20260920.tsv \
  2>&1 | tee ~/rehearsal-report.txt
```

The only thing you type is the identity. At
`Paste the age identity (AGE-SECRET-KEY-1...), then Enter. Nothing is echoed:`,
paste the key and press Enter. If you know the backup's recipient, add
`--recipient age1…` and the harness will refuse any other identity before
it decrypts anything.

The report file contains no secret, so it is safe to keep. The last lines
are the summary, `RESULT: PASS` or `RESULT: FAIL`, and the `WIPE:` line. The
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
- `enrollments` or `bootstraptokens`: read the counts on the line. "missing"
  or "new" against the baseline means the fleet changed since 2026-09-20, or
  the backup is incomplete.
- `v09.*` or `v06.*`: do not start step 3. The step-3 rollback cannot be
  trusted.
- `deus.migrate` or `deus.integrity`: do not start step 2. A failed migration
  leaves the database half-migrated (`schema.sql` is not applied in a
  transaction), so recovering from one needs the backup, not only the old
  binary.
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
tools/rehearsal/build.sh --selftest
~/.cache/malli-rehearsal/selftest/bin/malli-rehearsal-selftest /tmp/rehearsal-selftest
```

It builds made-up data: a NanoMDM store, a push certificate, and a
`deus.db` created by the old Deus, all encrypted to a throwaway key. It then
runs the harness as root of an unprivileged user namespace, in these cases:

- good data, with the identity on stdin and typed at the hidden prompt:
  every check passes;
- a wrong count;
- a corrupt archive;
- a v0.9 that leaves the store unreadable to v0.6;
- a failing migration;
- a Ctrl-C mid-run.

Every case must end with a complete wipe and with none of the planted
secret markers in the output. The markers are the identity, bootstrap
tokens, passwords, enrollment IDs and host names.

## Proposed Deus addition

A `-migrate-only` flag on `deus-server` would be the honest entry point for
this check. After flag parsing and before tokens are loaded, it would call
`store.Open(filepath.Join(*stateDir, "deus.db"))`, close the store and exit 0.
That would replace the `deus-rack-import -dry-run` stand-in. Applying
`schema.sql` inside one transaction would make a failed migration leave the
database as it was.
