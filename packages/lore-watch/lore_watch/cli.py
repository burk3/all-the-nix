"""lore-new: read the lore-watch mail.

    lore-new [list] [--since WHEN | --last-run | --runs N] [--search NAME]...
                    [--threads-only-ours] [--json]
        New messages: date, list, from, subject, Message-ID, search(es).
        WHEN is YYYY-MM-DD[THH:MM], or Nd / Nh (days/hours ago). Default 2d.
        --since filters by the message's Date header; --last-run/--runs N by
        when the sync timer added it (notmuch revisions in runs.jsonl).
    lore-new replies [same options]
        Messages in our own threads (searches with ours = true) that are not
        from us (ownAddresses). Default window 7d.
    lore-new show MSGID [--thread]
        The raw message (or the whole thread as mbox).
    lore-new status
        The last sync runs, failed searches, and messages per search.
    lore-new searches
        The configured searches and their queries.

Everything is read from the local notmuch index of the Maildir that the
lore-watch timer keeps; nothing touches the network.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
from email.parser import BytesHeaderParser
from email.utils import parseaddr
from pathlib import Path

from . import config as cfgmod
from .config import Config

WHEN_RE = re.compile(r"^(\d+)\s*([dhw])$")


def since_epoch(when: str, now: float | None = None) -> int:
    now = time.time() if now is None else now
    m = WHEN_RE.match(when.strip().lower())
    if m:
        n, unit = int(m.group(1)), m.group(2)
        return int(now - n * {"h": 3600, "d": 86400, "w": 7 * 86400}[unit])
    try:
        d = dt.datetime.fromisoformat(when.strip())
    except ValueError:
        raise SystemExit(f"lore-new: can't parse --since {when!r} (YYYY-MM-DD, 3d, 12h)")
    if d.tzinfo is None:
        d = d.astimezone()  # local time
    return int(d.timestamp())


def notmuch(cfg: Config, *args: str) -> str:
    if not (cfg.dir / ".notmuch").exists():
        raise SystemExit(
            f"lore-new: no notmuch index under {cfg.dir} yet; the lore-watch timer "
            "has not run (systemctl --user start lore-watch)"
        )
    p = subprocess.run(
        ["notmuch", f"--config={cfg.notmuch_config}", *args],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if p.returncode != 0:
        raise SystemExit(f"lore-new: notmuch {' '.join(args)}: {p.stderr.decode().strip()}")
    return p.stdout.decode(errors="replace")


def read_runs(cfg: Config) -> list[dict]:
    p = cfg.state_dir / "runs.jsonl"
    runs = []
    try:
        for line in p.read_text().splitlines():
            try:
                runs.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    except FileNotFoundError:
        pass
    return runs


def folder_term(names: list[str]) -> str:
    return "(" + " OR ".join(f'folder:"{n}"' for n in names) + ")"


def build_query(cfg: Config, a: argparse.Namespace, default_since: str,
                replies: bool = False) -> str:
    terms: list[str] = []
    if a.last_run or a.runs:
        runs = [r for r in read_runs(cfg) if r.get("revBefore") is not None
                and r.get("revAfter") is not None]
        n = a.runs or 1
        if not runs:
            raise SystemExit("lore-new: no completed sync run recorded yet")
        sel = runs[-n:]
        lo, hi = sel[0]["revBefore"] + 1, sel[-1]["revAfter"]
        if hi < lo:  # those runs added nothing
            return ""
        terms.append(f"lastmod:{lo}..{hi}")
    else:
        terms.append(f"date:@{since_epoch(a.since or default_since)}..")
    names = list(a.search or [])
    for n in names:
        if n not in cfg.searches and not (cfg.dir / n).is_dir():
            raise SystemExit(f"lore-new: unknown search {n!r} (lore-new searches)")
    if a.threads_only_ours or replies:
        ours = cfg.ours
        if not ours:
            raise SystemExit("lore-new: no search has ours = true")
        names = [n for n in names if n in ours] if names else ours
        if not names:
            raise SystemExit("lore-new: none of those searches are ours")
    if names:
        terms.append(folder_term(names))
    if replies and cfg.own_addresses:
        terms.append("NOT (" + " OR ".join(f'from:"{x}"' for x in cfg.own_addresses) + ")")
    return " AND ".join(terms)


def iter_messages(tree):
    """Walk `notmuch show --format=json` output: threads → [msg, replies]."""
    if isinstance(tree, dict):
        if "id" in tree:
            yield tree
        return
    if isinstance(tree, list):
        for t in tree:
            yield from iter_messages(t)


def list_name(path: str) -> str:
    try:
        with open(path, "rb") as f:
            h = BytesHeaderParser().parse(f)
    except OSError:
        return ""
    lid = h.get("List-Id") or ""
    m = re.search(r"<([^>]+)>", lid)
    if m:
        lid = m.group(1)
    if not lid:
        lid = h.get("X-Mailing-List") or ""
    lid = lid.strip().strip("<>")
    for suffix in (".vger.kernel.org", ".lists.infradead.org", ".lists.freedesktop.org",
                   ".lists.linux.dev", ".alsa-project.org"):
        if lid.endswith(suffix):
            return lid[: -len(suffix)]
    return lid.split("@")[0].split(".")[0] if lid else ""


def searches_of(cfg: Config, filenames: list[str]) -> list[str]:
    out = []
    for fn in filenames:
        try:
            rel = Path(fn).relative_to(cfg.dir)
        except ValueError:
            continue
        if rel.parts and rel.parts[0] not in out:
            out.append(rel.parts[0])
    return out


def collect(cfg: Config, query: str) -> list[dict]:
    raw = notmuch(cfg, "show", "--format=json", "--body=false",
                  "--entire-thread=false", query)
    rows = []
    for m in iter_messages(json.loads(raw) if raw.strip() else []):
        if not m.get("match", True):
            continue
        h = m.get("headers", {})
        files = m.get("filename") or []
        if isinstance(files, str):
            files = [files]
        name, addr = parseaddr(h.get("From", ""))
        rows.append({
            "date": dt.datetime.fromtimestamp(m.get("timestamp", 0)).strftime("%Y-%m-%d %H:%M"),
            "timestamp": m.get("timestamp", 0),
            "list": list_name(files[0]) if files else "",
            "from": name or addr,
            "fromAddress": addr,
            "subject": h.get("Subject", ""),
            "msgid": m["id"],
            "searches": searches_of(cfg, files),
            "inReplyTo": h.get("In-Reply-To", ""),
        })
    rows.sort(key=lambda r: r["timestamp"])
    return rows


def print_rows(rows: list[dict], as_json: bool) -> None:
    if as_json:
        for r in rows:
            print(json.dumps(r, ensure_ascii=False))
        return
    if not rows:
        print("(no messages)")
        return
    for r in rows:
        print(f"{r['date']}  {r['list'][:14]:<14}  {r['from'][:24]:<24}  {r['subject']}")
        print(f"{'':18}<{r['msgid']}>  [{', '.join(r['searches'])}]")


def cmd_list(cfg: Config, a: argparse.Namespace, replies: bool = False) -> int:
    q = build_query(cfg, a, "7d" if replies else "2d", replies=replies)
    if a.verbose:
        print(f"# notmuch query: {q or '(none: the selected runs added nothing)'}",
              file=sys.stderr)
    print_rows(collect(cfg, q) if q else [], a.json)
    return 0


def clean_msgid(m: str) -> str:
    m = m.strip()
    m = re.sub(r"^(?:https?://lore\.kernel\.org/[^/]+/)", "", m).rstrip("/")
    return m.strip("<>").removeprefix("id:")


def cmd_show(cfg: Config, a: argparse.Namespace) -> int:
    mid = clean_msgid(a.msgid)
    if notmuch(cfg, "count", f"id:{mid}").strip() == "0":
        print(f"lore-new: <{mid}> is not in the local copy; try `b4 mbox -o DIR {mid}`",
              file=sys.stderr)
        return 1
    if a.thread:
        tid = notmuch(cfg, "search", "--output=threads", f"id:{mid}").split()[0]
        sys.stdout.write(notmuch(cfg, "show", "--format=mbox", tid))
    else:
        sys.stdout.write(notmuch(cfg, "show", "--format=raw", f"id:{mid}"))
    return 0


def cmd_status(cfg: Config, a: argparse.Namespace) -> int:
    runs = read_runs(cfg)
    if not runs:
        print("no sync run recorded yet (systemctl --user start lore-watch)")
    else:
        last = runs[-1]
        when = dt.datetime.fromtimestamp(last["end"]).strftime("%Y-%m-%d %H:%M")
        age = max(0.0, (time.time() - last["end"]) / 60)
        print(f"last run: {when} ({age:.0f} min ago), {last.get('changed')} messages new "
              f"or changed, failed: {', '.join(last.get('failed') or []) or 'none'}")
        ok = [r for r in runs if not r.get("failed")]
        if ok and ok[-1] is not last:
            print("last fully successful run: "
                  + dt.datetime.fromtimestamp(ok[-1]["end"]).strftime("%Y-%m-%d %H:%M"))
    if (cfg.dir / ".notmuch").exists():
        total = notmuch(cfg, "count", "*").strip()
        print(f"{total} messages in {cfg.dir}")
        for n in sorted(cfg.searches):
            c = notmuch(cfg, "count", f'folder:"{n}"').strip()
            flag = " (ours)" if cfg.searches[n].ours else ""
            print(f"  {c:>6}  {n}{flag}")
    return 0


def cmd_searches(cfg: Config, a: argparse.Namespace) -> int:
    for n in sorted(cfg.searches):
        s = cfg.searches[n]
        flags = ",".join(f for f, on in (("threads", s.threads), ("ours", s.ours)) if on)
        print(f"{n}{' [' + flags + ']' if flags else ''}")
        if s.description:
            print(f"    {s.description}")
        print(f"    {s.query}")
    return 0


def add_window(p: argparse.ArgumentParser) -> None:
    g = p.add_mutually_exclusive_group()
    g.add_argument("--since", metavar="WHEN",
                   help="by message Date: YYYY-MM-DD[THH:MM] or Nd/Nh/Nw ago")
    g.add_argument("--last-run", action="store_true",
                   help="what the last sync run added")
    g.add_argument("--runs", type=int, metavar="N", help="what the last N sync runs added")
    p.add_argument("--search", action="append", metavar="NAME",
                   help="only this search (repeatable; see `lore-new searches`)")
    p.add_argument("--threads-only-ours", action="store_true",
                   help="only searches with ours = true (our own threads)")
    p.add_argument("--json", action="store_true", help="one JSON object per line")
    p.add_argument("-v", "--verbose", action="store_true", help="print the notmuch query")


def parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="lore-new",
        description="New lore.kernel.org mail from the local lore-watch copy.",
    )
    ap.add_argument("--config", type=Path, help="lore-watch config.json")
    sub = ap.add_subparsers(dest="cmd")
    add_window(sub.add_parser("list", help="new messages (the default)"))
    add_window(sub.add_parser("replies", help="new replies in our own threads, not from us"))
    s = sub.add_parser("show", help="print one message (raw), or its thread as mbox")
    s.add_argument("msgid")
    s.add_argument("--thread", action="store_true")
    sub.add_parser("status", help="sync runs and per-search counts")
    sub.add_parser("searches", help="configured searches")
    return ap


def main(argv: list[str] | None = None) -> int:
    try:
        return _main(argv)
    except BrokenPipeError:  # `lore-new | head`
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
        return 0


def _main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    cmds = {"list", "replies", "show", "status", "searches", "-h", "--help"}
    # `lore-new [--config X] [opts]` means `lore-new list [opts]`.
    i = 2 if argv[:1] == ["--config"] else 0
    if len(argv) <= i or argv[i] not in cmds:
        argv.insert(i, "list")
    a = parser().parse_args(argv)
    try:
        cfg = cfgmod.load(a.config)
    except cfgmod.ConfigError as e:
        print(f"lore-new: {e}", file=sys.stderr)
        return 2
    if a.cmd == "show":
        return cmd_show(cfg, a)
    if a.cmd == "status":
        return cmd_status(cfg, a)
    if a.cmd == "searches":
        return cmd_searches(cfg, a)
    return cmd_list(cfg, a, replies=(a.cmd == "replies"))


if __name__ == "__main__":
    sys.exit(main())
