#!/usr/bin/env python3
"""A stand-in for lei: keeps saved searches in $XDG_DATA_HOME/fake-lei.json and
writes messages from $FAKE_LEI_MAIL (a dir of <name>.eml files whose first
line is `X-Fake-Query: <query>`) into the Maildir output. `lei up` writes the
messages not yet delivered. $FAKE_LEI_FAIL=1 makes q/up fail like a network
error. Every call is logged to $FAKE_LEI_LOG."""

import json
import os
import sys
from pathlib import Path

args = sys.argv[1:]
state = Path(os.environ["XDG_DATA_HOME"]) / "fake-lei.json"
saved = json.loads(state.read_text()) if state.exists() else {}
with open(os.environ["FAKE_LEI_LOG"], "a") as f:
    f.write(json.dumps({"args": args, "runtime": os.environ.get("XDG_RUNTIME_DIR")}) + "\n")


def save():
    state.write_text(json.dumps(saved))


def deliver(out, query, threads):
    md = Path(out.removeprefix("maildir:"))
    for d in ("new", "cur", "tmp"):
        (md / d).mkdir(parents=True, exist_ok=True)
    n = 0
    for eml in sorted(Path(os.environ["FAKE_LEI_MAIL"]).glob("*.eml")):
        lines = eml.read_text().split("\n", 1)
        q = lines[0].removeprefix("X-Fake-Query: ").strip()
        if q != query:
            continue
        target = md / "cur" / (eml.stem + ":2,")
        if not target.exists():
            target.write_text(lines[1])
            n += 1
    print(f"# {n} written to {md}/ ({n} matches)", file=sys.stderr)


cmd = args[0]
if cmd == "ls-search":
    print(json.dumps([{"output": o, "q": [v["q"]]} for o, v in saved.items()]))
elif cmd == "q":
    if os.environ.get("FAKE_LEI_FAIL"):
        print("curl: (6) Could not resolve host: lore.kernel.org", file=sys.stderr)
        sys.exit(22)
    out = args[args.index("-o") + 1]
    query = args[-1]
    threads = "--threads" in args
    if out in saved:
        print("already saved", file=sys.stderr)
        sys.exit(1)
    # lei q clobbers the output
    md = Path(out.removeprefix("maildir:"))
    if md.exists():
        for p in md.glob("*/*"):
            p.unlink()
    deliver(out, query, threads)
    saved[out] = {"q": query, "threads": threads}
    save()
elif cmd == "up":
    if os.environ.get("FAKE_LEI_FAIL"):
        print("curl: (6) Could not resolve host: lore.kernel.org", file=sys.stderr)
        sys.exit(22)
    # like lei 2.1: up/forget-search want the bare path
    out = "maildir:" + args[-1]
    if out not in saved:
        sys.exit(1)
    deliver(out, saved[out]["q"], saved[out]["threads"])
elif cmd == "forget-search":
    assert not args[1].startswith("maildir:"), args
    saved.pop("maildir:" + args[1], None)
    save()
elif cmd == "daemon-kill":
    pass
else:
    sys.exit(f"fake lei: unsupported {args}")
