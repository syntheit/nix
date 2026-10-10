"""battlog: tiny battery/thermal logger.

  battlog collect            one sample -> SQLite (root, from launchd every 60s)
  battlog now                last sample
  battlog tail [-n N]        last N samples (default 20)
  battlog report [--days N]  summary (default 7 days)
"""
import argparse
import collections
import json
import os
import plistlib
import re
import sqlite3
import subprocess
import sys
import time

DB = os.environ.get("BATTLOG_DB", "/var/db/battlog/battlog.sqlite")
KEEP_DAYS = 30
MAX_GAP = 150  # seconds; longer gaps between samples = asleep / not running
PRESSURE = {"Nominal": 0, "Light": 1, "Moderate": 2, "Heavy": 3, "Trapping": 4, "Sleeping": 4}

SCHEMA = """
CREATE TABLE IF NOT EXISTS samples(
  ts INTEGER PRIMARY KEY,   -- unix seconds
  pct INTEGER,              -- battery %
  watts REAL,               -- system draw from battery, W (negative = charging)
  charging INTEGER, ac INTEGER,
  batt_temp REAL,           -- degC, NULL if the OS does not expose it
  cpu_mw REAL, gpu_mw REAL, ane_mw REAL,
  thermal_pressure TEXT,
  cycles INTEGER, full_mah INTEGER, design_mah INTEGER,
  assertions TEXT,          -- json list of "proc:AssertionType" preventing sleep
  top TEXT                  -- json [[name, energy_impact], ...] top ~8
);
"""


def run(cmd, timeout=15):
    try:
        return subprocess.run(cmd, capture_output=True, timeout=timeout).stdout
    except Exception:
        return b""


# ---------------------------------------------------------------- collect

def battery():
    out = run(["/usr/sbin/ioreg", "-arn", "AppleSmartBattery"])
    try:
        d = plistlib.loads(out)[0]
    except Exception:
        return {}
    bd = d.get("BatteryData", {}) or {}
    amp = d.get("InstantAmperage", d.get("Amperage", 0)) or 0
    if amp >= 2**63:  # unsigned 64-bit two's complement
        amp -= 2**64
    volt = d.get("Voltage", 0) or 0
    temp = d.get("Temperature")
    return {
        "pct": d.get("CurrentCapacity"),
        "watts": round(-amp * volt / 1e6, 3),  # >0 discharging
        "charging": int(bool(d.get("IsCharging"))),
        "ac": int(bool(d.get("ExternalConnected"))),
        "batt_temp": round(temp / 100.0, 2) if temp else None,
        "cycles": d.get("CycleCount"),
        "full_mah": d.get("AppleRawMaxCapacity") or bd.get("NominalChargeCapacity") or bd.get("FullChargeCapacity"),
        "design_mah": d.get("DesignCapacity") or bd.get("DesignCapacity"),
    }


def assertions():
    txt = run(["/usr/bin/pmset", "-g", "assertions"]).decode(errors="replace")
    seen = []
    for m in re.finditer(r"pid \d+\(([^)]+)\):\s+\[[^\]]+\]\s+\S+\s+(\w+)", txt):
        name, kind = m.groups()
        if name == "powerd":  # display-on bookkeeping, not a culprit
            continue
        if kind.startswith(("Prevent", "NoIdle", "NoDisplay")) or kind in ("BackgroundTask", "NetworkClientActive"):
            e = f"{name}:{kind}"
            if e not in seen:
                seen.append(e)
    return seen


def power():
    out = run(
        ["/usr/bin/powermetrics", "-n", "1", "-i", "1000",
         "--samplers", "cpu_power,gpu_power,thermal,tasks",
         "--show-process-energy", "-f", "plist"],
        timeout=20,
    ).replace(b"\x00", b"").strip()
    if not out:
        return {}
    try:
        d = plistlib.loads(out)
    except Exception:
        return {}
    p = d.get("processor", {}) or {}
    g = d.get("gpu", {}) or {}

    def mw(*vals):
        for v in vals:
            if isinstance(v, (int, float)):
                return float(v)
        return None

    tasks = []
    for t in d.get("tasks", []) or []:
        name = t.get("name", "?")
        if name in ("ALL_TASKS", "powermetrics", "battlog"):
            continue
        ei = t.get("energy_impact_per_s", t.get("energy_impact"))
        if ei:
            tasks.append([name, round(float(ei), 1)])
    tasks.sort(key=lambda x: -x[1])
    return {
        "cpu_mw": mw(p.get("cpu_power")),
        "gpu_mw": mw(p.get("gpu_power"), g.get("gpu_power")),
        "ane_mw": mw(p.get("ane_power")),
        "thermal_pressure": d.get("thermal_pressure"),
        "top": json.dumps(tasks[:8], separators=(",", ":")),
    }


def collect():
    os.umask(0o022)
    os.makedirs(os.path.dirname(DB), mode=0o755, exist_ok=True)
    con = sqlite3.connect(DB, timeout=10)
    con.executescript(SCHEMA)
    row = {"ts": int(time.time())}
    row.update(battery())
    row.update(power())
    row["assertions"] = json.dumps(assertions(), separators=(",", ":"))
    cols = ",".join(row)
    con.execute(f"INSERT OR REPLACE INTO samples({cols}) VALUES({','.join('?' * len(row))})", list(row.values()))
    con.execute("DELETE FROM samples WHERE ts < ?", (row["ts"] - KEEP_DAYS * 86400,))
    con.commit()
    con.close()
    os.chmod(DB, 0o644)


# ----------------------------------------------------------------- reading

def open_db():
    if not os.path.exists(DB):
        sys.exit(f"no database at {DB} yet (daemon has not run)")
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con


def fmt_ts(ts):
    return time.strftime("%a %d %H:%M", time.localtime(ts))


def fmt_row(r):
    top = json.loads(r["top"] or "[]")[:3]
    watts = f"{r['watts']:.1f}W" if r["watts"] is not None else "?W"
    cpu = f"{(r['cpu_mw'] or 0) / 1000:.1f}" if r["cpu_mw"] is not None else "?"
    gpu = f"{(r['gpu_mw'] or 0) / 1000:.1f}" if r["gpu_mw"] is not None else "?"
    tmp = f" {r['batt_temp']:.0f}C" if r["batt_temp"] else ""
    return (f"{fmt_ts(r['ts'])} {r['pct']}%{'+' if r['charging'] else ('~' if r['ac'] else '-')} {watts} "
            f"cpu {cpu}W gpu {gpu}W {r['thermal_pressure'] or '?'}{tmp} | "
            + ", ".join(f"{n} {e:.0f}" for n, e in top))


def cmd_now(_):
    con = open_db()
    r = con.execute("SELECT * FROM samples ORDER BY ts DESC LIMIT 1").fetchone()
    if not r:
        sys.exit("empty")
    print(fmt_row(r))
    print("age:", int(time.time() - r["ts"]), "s; assertions:", ", ".join(json.loads(r["assertions"] or "[]")) or "none")


def cmd_tail(a):
    con = open_db()
    rows = con.execute("SELECT * FROM samples ORDER BY ts DESC LIMIT ?", (a.n,)).fetchall()
    for r in reversed(rows):
        print(fmt_row(r))


def wake_reasons(since):
    out = run(["/usr/bin/pmset", "-g", "log"], timeout=60).decode(errors="replace")
    cutoff = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(since))
    reasons = collections.Counter()
    sleeps = 0
    for line in out.splitlines():
        if len(line) < 20 or line[:19] < cutoff:
            continue
        m = re.match(r"\S+ \S+ [-+]\d{4} (Wake|DarkWake|Sleep)\s+(.*)", line)
        if not m or m.group(2).startswith("Requests"):
            continue
        kind, rest = m.groups()
        if kind == "Sleep":
            sleeps += 1
            continue
        why = re.search(r"due to (.*?)(?: Using| Charge:|$)", rest)
        reason = why.group(1).strip() if why else rest[:60]
        reason = re.sub(r"\(0x[0-9a-fA-F]+\)", "", reason).strip()
        reasons[f"{kind}: {reason}"] += 1
    return sleeps, reasons


def cmd_report(a):
    con = open_db()
    since = int(time.time() - a.days * 86400)
    rows = con.execute("SELECT * FROM samples WHERE ts >= ? ORDER BY ts", (since,)).fetchall()
    if len(rows) < 2:
        sys.exit("not enough samples yet")
    print(f"battlog: {len(rows)} samples, {fmt_ts(rows[0]['ts'])} -> {fmt_ts(rows[-1]['ts'])}")

    # time-weight each sample by the gap to the previous one, capped so sleep
    # gaps (no sampling) do not count as awake time
    w = [0.0]
    for p, r in zip(rows, rows[1:]):
        w.append(min(r["ts"] - p["ts"], MAX_GAP))
    tot = sum(w) or 1
    ac_t = sum(x for x, r in zip(w, rows) if r["ac"])
    batt = [(x, r) for x, r in zip(w, rows) if not r["ac"] and r["watts"] is not None]
    bt = sum(x for x, _ in batt)
    print(f"awake {tot / 3600:.1f}h, on AC {100 * ac_t / tot:.0f}%, on battery {bt / 3600:.1f}h")

    # health / capacity
    last = rows[-1]
    full, design = last["full_mah"], last["design_mah"]
    health = f"{100 * full / design:.0f}% ({full}/{design} mAh)" if full and design else "n/a"
    # watts: use only samples where discharge reading is meaningful
    if bt:
        avg = sum(x * r["watts"] for x, r in batt) / bt
        line = f"on-battery avg {avg:.1f} W"
        if avg > 0.5 and design:
            wh = design * 11.4 / 1000 * (full / design if full else 1)
            line += f" -> ~{wh / avg:.1f} h per full charge (~{wh:.0f} Wh)"
        print(line)
        cpu = [(x, r["cpu_mw"]) for x, r in batt if r["cpu_mw"] is not None]
        gpu = [(x, r["gpu_mw"]) for x, r in batt if r["gpu_mw"] is not None]
        if cpu:
            print(f"  avg cpu {sum(x * v for x, v in cpu) / sum(x for x, _ in cpu) / 1000:.2f} W"
                  + (f", gpu {sum(x * v for x, v in gpu) / sum(x for x, _ in gpu) / 1000:.2f} W" if gpu else ""))

        # top processes by energy impact on battery
        agg = collections.Counter()
        for x, r in batt:
            for n, e in json.loads(r["top"] or "[]"):
                agg[n] += e * x
        s = sum(agg.values()) or 1
        print("top energy (battery, share of logged top-8 impact):")
        for n, v in agg.most_common(10):
            print(f"  {100 * v / s:5.1f}%  {n}")
        ag = collections.Counter()
        for x, r in batt:
            for e in json.loads(r["assertions"] or "[]"):
                ag[e] += x
        if ag:
            print("sleep-preventing assertions on battery (hours held):")
            for e, v in ag.most_common(6):
                print(f"  {v / 3600:5.1f}h  {e}")
    else:
        print("no battery samples in range")

    # hottest
    def heat(r):
        return (PRESSURE.get(r["thermal_pressure"], 0), r["batt_temp"] or 0, (r["cpu_mw"] or 0) + (r["gpu_mw"] or 0))
    print("hottest moments (thermal pressure, battery temp, cpu+gpu):")
    picked = []
    for r in sorted(rows, key=heat, reverse=True):
        if all(abs(r["ts"] - q["ts"]) > 900 for q in picked):
            picked.append(r)
        if len(picked) == 5:
            break
    for r in picked:
        print("  " + fmt_row(r))

    # sleep gaps on battery (overnight drain)
    gaps = []
    for p, r in zip(rows, rows[1:]):
        dt = r["ts"] - p["ts"]
        if dt > 600 and not p["ac"] and not r["ac"] and p["pct"] is not None and r["pct"] is not None:
            gaps.append((p, r, dt))
    print("sleep drain (gaps >10min with no samples, on battery both ends):")
    if gaps:
        hrs = sum(dt for *_, dt in gaps) / 3600
        lost = sum(p["pct"] - r["pct"] for p, r, _ in gaps)
        print(f"  {len(gaps)} gaps, {hrs:.1f}h asleep, {lost}% lost -> {lost / hrs:.2f} %/h")
        night = [(p, r, dt) for p, r, dt in gaps
                 if time.localtime(p["ts"]).tm_hour >= 22 or time.localtime(p["ts"]).tm_hour < 7]
        if night:
            nh = sum(dt for *_, dt in night) / 3600
            nl = sum(p["pct"] - r["pct"] for p, r, _ in night)
            print(f"  overnight-start gaps: {nh:.1f}h, {nl}% -> {nl / nh:.2f} %/h")
        for p, r, dt in sorted(gaps, key=lambda g: -(g[0]["pct"] - g[1]["pct"]) / (g[2] / 3600))[:3]:
            if dt >= 1800:
                print(f"  worst: {fmt_ts(p['ts'])} -> {fmt_ts(r['ts'])} ({dt / 3600:.1f}h) {p['pct']}% -> {r['pct']}%")
    else:
        print("  none")
    sleeps, reasons = wake_reasons(since)
    print(f"wakes ({sleeps} sleeps in pmset log, top reasons):")
    for k, v in reasons.most_common(8):
        print(f"  {v:4d}  {k}")
    print(f"battery health: {health}, {last['cycles']} cycles")


def main():
    ap = argparse.ArgumentParser(prog="battlog")
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("collect").set_defaults(f=lambda a: collect())
    sp.add_parser("now").set_defaults(f=cmd_now)
    t = sp.add_parser("tail")
    t.add_argument("-n", type=int, default=20)
    t.set_defaults(f=cmd_tail)
    r = sp.add_parser("report")
    r.add_argument("--days", type=float, default=7)
    r.set_defaults(f=cmd_report)
    a = ap.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
