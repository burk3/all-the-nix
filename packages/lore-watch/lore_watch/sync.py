"""lore-watch-sync: bring every saved lei search up to date, then index.

Run by the lore-watch systemd user timer (modules/home/lore-watch.nix). For
each search in the config:

  * if lei has no saved search for its Maildir, or the query/threads changed
    since the last successful create: forget the old saved search (if any)
    and `lei q` it afresh into <dir>/<name> (this clobbers that Maildir, which
    is what a changed query should do);
  * otherwise `lei up` it: lei asks lore only for mail newer than its last
    successful query minus a lookback (--remote-fudge-time): quickLookback
    (1 day) on most runs, the search's own `lookback` once every
    lookbackEvery (6 h). Thread searches need the long one to pick up replies
    to older matches; doing it every 30 minutes would re-download days of
    threads from lore each time.

Then `notmuch new` indexes the Maildir root, and the run (notmuch revisions
before/after, failed searches) is appended to <stateDir>/runs.jsonl, which
`lore-new --last-run` and `lore-new status` read.

Read-only towards lore: lei only queries lore.kernel.org over HTTPS. lei's
own state (saved searches, its daemon socket) is kept apart from any
interactive lei use, under <stateDir>/lei and $XDG_RUNTIME_DIR/lore-watch.

A failed search (network down, lore timing out) is logged and skipped; the
others still run, notmuch still indexes, and the next timer run retries it.
The exit status is 1 if any search failed, so `systemctl --user status
lore-watch` shows it. A second run while one is in progress exits at once.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from . import config as cfgmod
from .config import Config, Search

# sd-daemon(3) priority prefixes; journald turns them into PRIORITY=.
ERR, WARNING, NOTICE, INFO = "<3>", "<4>", "<5>", "<6>"


def log(prio: str, msg: str) -> None:
    for line in msg.rstrip("\n").splitlines() or [""]:
        print(f"{prio}{line}", flush=True)


def lei_env(cfg: Config) -> dict[str, str]:
    """Environment that gives lei its own config, store and daemon."""
    env = dict(os.environ)
    base = cfg.state_dir / "lei"
    env["XDG_CONFIG_HOME"] = str(base / "config")
    env["XDG_DATA_HOME"] = str(base / "data")
    env["XDG_CACHE_HOME"] = str(base / "cache")
    env["XDG_STATE_HOME"] = str(base / "state")
    # lei's socket is $XDG_RUNTIME_DIR/lei/5.seq.sock and must fit in
    # sun_path (108 bytes), so keep it short.
    rt = os.environ.get("XDG_RUNTIME_DIR")
    run = Path(rt) / "lore-watch" if rt else Path(f"/tmp/lore-watch-{os.getuid()}")
    if len(str(run / "lei" / "5.seq.sock")) > 100:
        run = Path(f"/tmp/lore-watch-{os.getuid()}")
    run.mkdir(mode=0o700, parents=True, exist_ok=True)
    env["XDG_RUNTIME_DIR"] = str(run)
    for d in ("config", "data", "cache", "state"):
        (base / d).mkdir(parents=True, exist_ok=True)
    return env


def output_of(cfg: Config, name: str) -> str:
    """The output as `lei q -o` takes it and `lei ls-search` lists it."""
    return f"maildir:{cfg.dir / name}"


def folder_of(cfg: Config, name: str) -> str:
    """The output as `lei up` and `lei forget-search` take it (no prefix)."""
    return str(cfg.dir / name)


def run(cmd: list[str], env: dict[str, str], timeout: int) -> tuple[int, str]:
    try:
        p = subprocess.run(
            cmd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired as e:
        out = e.stdout.decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        return 124, out + f"\ntimed out after {timeout}s"
    except FileNotFoundError as e:
        return 127, str(e)


def saved_outputs(env: dict[str, str]) -> set[str] | None:
    rc, out = run(["lei", "ls-search", "-f", "json"], env, 120)
    if rc != 0:
        log(ERR, f"lei ls-search failed ({rc}):\n{out}")
        return None
    # lei may print '# ...' progress lines before the JSON.
    text = "\n".join(l for l in out.splitlines() if not l.startswith("#")).strip()
    if not text:
        return set()
    try:
        return {s["output"] for s in json.loads(text)}
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        log(ERR, f"lei ls-search: unexpected output ({e}):\n{out}")
        return None


def lei_q_cmd(cfg: Config, s: Search) -> list[str]:
    cmd = [
        "lei", "q",
        "--only", cfg.external,  # lore only; nothing from a local store
        "--no-import-remote",  # don't keep a second copy in lei's store
        "--torsocks=no",
        "--dedupe=mid",  # one copy per Message-ID, not one per list
    ]
    if s.threads:
        cmd.append("--threads")
    cmd += ["-o", output_of(cfg, s.name), s.query]
    return cmd


def lei_up_cmd(cfg: Config, s: Search, deep: bool = False) -> list[str]:
    cmd = ["lei", "up"]
    fudge = s.lookback if (deep and s.lookback) else cfg.quick_lookback
    if fudge:
        cmd.append(f"--remote-fudge-time={fudge}")
    return cmd + [folder_of(cfg, s.name)]


def deep_path(cfg: Config, name: str) -> Path:
    return cfg.state_dir / "deep" / name


def deep_due(cfg: Config, s: Search, now: float) -> bool:
    """Whether this run uses the search's own lookback (every lookbackEvery)."""
    if not s.lookback:
        return False
    try:
        return now - deep_path(cfg, s.name).stat().st_mtime >= cfg.lookback_every
    except FileNotFoundError:
        return True


def mark_deep(cfg: Config, name: str, now: float) -> None:
    p = deep_path(cfg, name)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.touch()
    os.utime(p, (now, now))


def spec_path(cfg: Config, name: str) -> Path:
    return cfg.state_dir / "specs" / f"{name}.json"


def read_spec(cfg: Config, name: str) -> dict | None:
    try:
        return json.loads(spec_path(cfg, name).read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def write_spec(cfg: Config, name: str, spec: dict) -> None:
    p = spec_path(cfg, name)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(spec, sort_keys=True) + "\n")
    tmp.replace(p)


def sync_search(cfg: Config, s: Search, saved: set[str], env: dict[str, str]) -> bool:
    out = output_of(cfg, s.name)
    spec = s.spec(cfg.external)
    now = time.time()
    if out in saved and read_spec(cfg, s.name) == spec:
        deep = deep_due(cfg, s, now)
        rc, text = run(lei_up_cmd(cfg, s, deep), env, cfg.search_timeout)
        action = f"up ({s.lookback} lookback)" if deep else "up"
        if rc == 0 and deep:
            mark_deep(cfg, s.name, now)
    else:
        if out in saved:
            log(NOTICE, f"{s.name}: query changed, re-creating the saved search")
            frc, ftext = run(["lei", "forget-search", folder_of(cfg, s.name)], env, 120)
            if frc != 0:
                log(ERR, f"{s.name}: lei forget-search failed ({frc}):\n{ftext}")
                return False
        else:
            log(NOTICE, f"{s.name}: creating the saved search")
        # The spec is only written after a successful create, so a failed
        # or interrupted create is retried from scratch on the next run.
        spec_path(cfg, s.name).unlink(missing_ok=True)
        (cfg.dir / s.name).parent.mkdir(parents=True, exist_ok=True)
        rc, text = run(lei_q_cmd(cfg, s), env, cfg.search_timeout)
        action = "q"
        if rc == 0:
            write_spec(cfg, s.name, spec)
            mark_deep(cfg, s.name, now)  # a create fetched everything
    if rc != 0:
        log(WARNING, f"{s.name}: lei {action} failed ({rc}), will retry next run:\n{text}")
        return False
    summary = [l for l in text.splitlines() if "written to" in l or "matches" in l]
    log(INFO, f"{s.name}: lei {action} ok" + (f": {summary[-1].lstrip('# ')}" if summary else ""))
    return True


def forget_removed(cfg: Config, saved: set[str], env: dict[str, str]) -> None:
    specs = cfg.state_dir / "specs"
    if not specs.is_dir():
        return
    for p in sorted(specs.glob("*.json")):
        name = p.stem
        if name in cfg.searches:
            continue
        if output_of(cfg, name) in saved:
            rc, text = run(["lei", "forget-search", folder_of(cfg, name)], env, 120)
            if rc != 0:
                log(WARNING, f"{name}: lei forget-search failed ({rc}):\n{text}")
                continue
        p.unlink()
        log(NOTICE, f"{name}: removed from the config; saved search forgotten, "
                    f"Maildir {cfg.dir / name} kept (delete it by hand)")


def notmuch(cfg: Config, *args: str, timeout: int = 1800) -> tuple[int, str]:
    return run(["notmuch", f"--config={cfg.notmuch_config}", *args], dict(os.environ), timeout)


def notmuch_revision(cfg: Config) -> int | None:
    if not (cfg.dir / ".notmuch").exists():
        return 0
    rc, out = notmuch(cfg, "count", "--lastmod", "*", timeout=120)
    if rc != 0:
        log(WARNING, f"notmuch count --lastmod failed ({rc}):\n{out}")
        return None
    try:
        return int(out.split()[2])
    except (IndexError, ValueError):
        return None


def append_run(cfg: Config, record: dict) -> None:
    p = cfg.state_dir / "runs.jsonl"
    with p.open("a") as f:
        f.write(json.dumps(record, sort_keys=True) + "\n")


def sync(cfg: Config, only: list[str] | None = None) -> int:
    cfg.state_dir.mkdir(parents=True, exist_ok=True)
    cfg.dir.mkdir(parents=True, exist_ok=True)
    lock = open(cfg.state_dir / "lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log(NOTICE, "another lore-watch-sync is running; nothing to do")
        return 0

    start = time.time()
    env = lei_env(cfg)
    failed: list[str] = []
    try:
        saved = saved_outputs(env)
        if saved is None:
            failed = sorted(cfg.searches)
        else:
            names = sorted(cfg.searches) if not only else only
            for name in names:
                if not sync_search(cfg, cfg.searches[name], saved, env):
                    failed.append(name)
            if not only:
                forget_removed(cfg, saved, env)
    finally:
        # Our lei daemon is private to lore-watch; don't leave it running.
        run(["lei", "daemon-kill"], env, 60)

    rev_before = notmuch_revision(cfg)
    rc, out = notmuch(cfg, "new", "--quiet")
    if rc != 0:
        log(ERR, f"notmuch new failed ({rc}):\n{out}")
        failed.append("(notmuch new)")
    elif out.strip():
        log(INFO, out)
    rev_after = notmuch_revision(cfg)
    added = None
    if rev_before is not None and rev_after is not None and rc == 0:
        if rev_before == rev_after:
            added = 0
        else:
            c, o = notmuch(cfg, "count", f"lastmod:{rev_before + 1}..{rev_after}", timeout=120)
            added = int(o.strip()) if c == 0 and o.strip().isdigit() else None
    record = {
        "start": round(start),
        "end": round(time.time()),
        "revBefore": rev_before,
        "revAfter": rev_after,
        "changed": added,
        "failed": failed,
        "searches": sorted(cfg.searches) if not only else only,
    }
    append_run(cfg, record)
    log(INFO if not failed else WARNING,
        f"done: {added if added is not None else '?'} messages new or changed, "
        f"{len(failed)} failed{': ' + ', '.join(failed) if failed else ''}")
    return 1 if failed else 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="lore-watch-sync",
        description="Update the lore-watch saved lei searches and index them with notmuch.",
    )
    ap.add_argument("--config", type=Path, help="config.json (default: $LORE_WATCH_CONFIG "
                    "or ~/.config/lore-watch/config.json)")
    ap.add_argument("--check", action="store_true",
                    help="validate the config and print each search's create (lei q) and "
                         "update (lei up) command; no network")
    ap.add_argument("--search", action="append", metavar="NAME",
                    help="only this search (repeatable)")
    a = ap.parse_args(argv)
    try:
        cfg = cfgmod.load(a.config)
    except cfgmod.ConfigError as e:
        log(ERR, str(e))
        return 2
    if a.search:
        unknown = [n for n in a.search if n not in cfg.searches]
        if unknown:
            log(ERR, f"unknown search(es): {', '.join(unknown)}")
            return 2
    if a.check:
        import shlex
        for name in a.search or sorted(cfg.searches):
            print(shlex.join(lei_q_cmd(cfg, cfg.searches[name])))
            s = cfg.searches[name]
            print(shlex.join(lei_up_cmd(cfg, s)))
            if s.lookback:
                print(shlex.join(lei_up_cmd(cfg, s, deep=True)))
        print(f"# {len(cfg.searches)} searches, Maildir root {cfg.dir}")
        return 0
    return sync(cfg, a.search)


if __name__ == "__main__":
    sys.exit(main())
