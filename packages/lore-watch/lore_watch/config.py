"""lore-watch configuration (written by modules/home/lore-watch.nix).

The home-manager module writes ~/.config/lore-watch/config.json:

    {
      "dir": "/home/burke/mail/lore",            # Maildir root, one folder per search
      "stateDir": "/home/burke/.local/state/lore-watch",
      "notmuchConfig": "/home/burke/.config/lore-watch/notmuch-config",
      "external": "https://lore.kernel.org/all/",
      "ownAddresses": ["burke.cates@gmail.com"],
      "searchTimeout": 900,
      "quickLookback": "1.day",        # lei up --remote-fudge-time on most runs
      "lookbackEvery": 21600,          # seconds between runs that use each
                                       # search's own (longer) lookback
      "searches": {
        "name": {"query": "...", "threads": false, "ours": false,
                 "description": "..."}
      },
      "searchFiles": ["/home/burke/.config/lore-watch/searches.json"]
    }

Each searchFiles entry that exists is a JSON object of more searches in the
same form ({"name": {"query": ...}}), kept outside the Nix config (personal
searches that shouldn't be in a public repo). They are merged over
"searches": a name in a file replaces the module's search of that name. A
missing file is skipped.

`lore-watch-sync --config PATH` and `lore-new` both read it. lore-new finds it
via $LORE_WATCH_CONFIG or $XDG_CONFIG_HOME/lore-watch/config.json.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class ConfigError(Exception):
    pass


@dataclass(frozen=True)
class Search:
    name: str
    query: str
    threads: bool = False
    ours: bool = False
    description: str = ""
    # `lei up --remote-fudge-time`: how far before the last successful run
    # each update asks lore again (lei's own default is 2 days). With
    # threads, a reply only arrives if a match within this window is in its
    # thread, so thread searches want a longer one.
    lookback: str | None = None

    def spec(self, external: str) -> dict:
        """What lei is asked for. A change here re-creates the saved search."""
        return {
            "query": self.query,
            "threads": self.threads,
            "external": external,
            "dedupe": "mid",
        }


@dataclass
class Config:
    dir: Path
    state_dir: Path
    notmuch_config: Path
    external: str = "https://lore.kernel.org/all/"
    own_addresses: list[str] = field(default_factory=list)
    search_timeout: int = 900
    quick_lookback: str | None = "1.day"
    lookback_every: int = 6 * 3600
    searches: dict[str, Search] = field(default_factory=dict)
    path: Path | None = None

    @property
    def ours(self) -> list[str]:
        return sorted(n for n, s in self.searches.items() if s.ours)


def default_config_path() -> Path:
    env = os.environ.get("LORE_WATCH_CONFIG")
    if env:
        return Path(env)
    xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(xdg) / "lore-watch" / "config.json"


def load(path: Path | None = None) -> Config:
    path = Path(path) if path else default_config_path()
    try:
        raw = json.loads(path.read_text())
    except FileNotFoundError:
        raise ConfigError(
            f"no lore-watch config at {path}: lore-watch is not set up on this "
            "machine. Query lore live with lei/b4 instead."
        ) from None
    except json.JSONDecodeError as e:
        raise ConfigError(f"{path}: {e}") from None
    raw = dict(raw)
    searches = dict(raw.get("searches", {}))
    for f in raw.get("searchFiles", []):
        f = Path(os.path.expanduser(f))
        try:
            extra = json.loads(f.read_text())
        except FileNotFoundError:
            continue
        except json.JSONDecodeError as e:
            raise ConfigError(f"{f}: {e}") from None
        if not isinstance(extra, dict):
            raise ConfigError(f"{f}: expected an object of searches")
        searches.update(extra)
    raw["searches"] = searches
    return parse(raw, path)


def parse(raw: dict, path: Path | None = None) -> Config:
    for key in ("dir", "stateDir", "notmuchConfig", "searches"):
        if key not in raw:
            raise ConfigError(f"config: missing {key!r}")
    searches = {}
    for name, s in raw["searches"].items():
        if not NAME_RE.match(name):
            raise ConfigError(f"search name {name!r}: use letters, digits, . _ -")
        if not isinstance(s.get("query"), str) or not s["query"].strip():
            raise ConfigError(f"search {name!r}: empty query")
        searches[name] = Search(
            name=name,
            query=s["query"],
            threads=bool(s.get("threads", False)),
            ours=bool(s.get("ours", False)),
            description=s.get("description", ""),
            lookback=s.get("lookback") or None,
        )
    return Config(
        dir=Path(raw["dir"]),
        state_dir=Path(raw["stateDir"]),
        notmuch_config=Path(raw["notmuchConfig"]),
        external=raw.get("external", "https://lore.kernel.org/all/"),
        own_addresses=[a.lower() for a in raw.get("ownAddresses", [])],
        search_timeout=int(raw.get("searchTimeout", 900)),
        quick_lookback=raw.get("quickLookback", "1.day") or None,
        lookback_every=int(raw.get("lookbackEvery", 6 * 3600)),
        searches=searches,
        path=path,
    )
