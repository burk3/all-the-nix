"""lore-watch-sync against a fake lei and the real notmuch, then lore-new."""

import json
import os
import shutil
import stat
import sys
import time
from email.utils import formatdate
from pathlib import Path

import pytest

from lore_watch import cli, config, sync

HERE = Path(__file__).parent


def msg(mid, frm, subject, when, query, list_id="linux-arm-msm.vger.kernel.org",
        reply_to=None):
    hdr = [
        f"X-Fake-Query: {query}",
        f"From: {frm}",
        f"Subject: {subject}",
        f"Date: {formatdate(when)}",
        f"Message-ID: <{mid}>",
        f"List-Id: <{list_id}>",
    ]
    if reply_to:
        hdr += [f"In-Reply-To: <{reply_to}>", f"References: <{reply_to}>"]
    return "\n".join(hdr) + "\n\nbody\n"


@pytest.fixture
def env(tmp_path, monkeypatch):
    if not shutil.which("notmuch"):
        pytest.skip("notmuch not on PATH")
    bindir = tmp_path / "bin"
    bindir.mkdir()
    lei = bindir / "lei"
    lei.write_text(f"#!{sys.executable}\n" + (HERE / "fake_lei.py").read_text())
    lei.chmod(lei.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setenv("PATH", f"{bindir}:{os.environ['PATH']}")
    mail = tmp_path / "fake-mail"
    mail.mkdir()
    monkeypatch.setenv("FAKE_LEI_MAIL", str(mail))
    monkeypatch.setenv("FAKE_LEI_LOG", str(tmp_path / "lei.log"))
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path / "run"))
    (tmp_path / "run").mkdir()

    store = tmp_path / "lore"
    nmcfg = tmp_path / "notmuch-config"
    nmcfg.write_text(f"[database]\npath={store}\n[new]\ntags=\nignore=\n"
                     "[maildir]\nsynchronize_flags=false\n")
    raw = {
        "dir": str(store),
        "stateDir": str(tmp_path / "state"),
        "notmuchConfig": str(nmcfg),
        "external": "https://lore.kernel.org/all/",
        "ownAddresses": ["burke.cates@gmail.com"],
        "searches": {
            "ours-c2": {"query": "m:root@x", "threads": True, "ours": True,
                        "lookback": "10.years"},
            "topic-glymur": {"query": "s:glymur AND d:2026-10-01..", "threads": False},
        },
    }
    cfgpath = tmp_path / "config.json"
    cfgpath.write_text(json.dumps(raw))
    monkeypatch.setenv("LORE_WATCH_CONFIG", str(cfgpath))

    now = time.time()
    (mail / "a.eml").write_text(msg("root@x", "Burke Cates <burke.cates@gmail.com>",
                                    "Glymur USB Gen2 fails", now - 3600, "m:root@x"))
    (mail / "b.eml").write_text(msg("glymur1@q", "Konrad Dybcio <konrad@q>",
                                    "[PATCH] arm64: dts: qcom: glymur: foo", now - 1800,
                                    "s:glymur AND d:2026-10-01..",
                                    list_id="devicetree.vger.kernel.org"))

    class E:
        pass

    e = E()
    e.tmp, e.mail, e.store, e.cfgpath, e.raw = tmp_path, mail, store, cfgpath, raw
    e.log = tmp_path / "lei.log"
    return e


def lei_calls(e):
    return [json.loads(l)["args"] for l in e.log.read_text().splitlines()]


def test_parse_rejects_bad_names():
    with pytest.raises(config.ConfigError):
        config.parse({"dir": "/x", "stateDir": "/y", "notmuchConfig": "/z",
                      "searches": {"../evil": {"query": "a"}}})
    with pytest.raises(config.ConfigError):
        config.parse({"dir": "/x", "stateDir": "/y", "notmuchConfig": "/z",
                      "searches": {"ok": {"query": " "}}})


def test_lei_q_command():
    cfg = config.parse({"dir": "/m", "stateDir": "/s", "notmuchConfig": "/n",
                        "searches": {"a": {"query": "s:x AND d:2026-10-01..", "threads": True}}})
    cmd = sync.lei_q_cmd(cfg, cfg.searches["a"])
    assert cmd[:2] == ["lei", "q"]
    assert "--threads" in cmd and "--no-import-remote" in cmd and "--dedupe=mid" in cmd
    assert cmd[cmd.index("--only") + 1] == "https://lore.kernel.org/all/"
    assert cmd[-3:] == ["-o", "maildir:/m/a", "s:x AND d:2026-10-01.."]


def test_since_epoch():
    now = 1_800_000_000
    assert cli.since_epoch("2d", now) == now - 2 * 86400
    assert cli.since_epoch("12h", now) == now - 12 * 3600
    assert cli.since_epoch("2026-10-01T00:00+00:00") == 1790812800
    with pytest.raises(SystemExit):
        cli.since_epoch("last tuesday")


def test_sync_create_then_up_then_change(env, capsys):
    cfg = config.load()
    assert sync.sync(cfg) == 0
    calls = lei_calls(env)
    assert [c[0] for c in calls].count("q") == 2
    # private lei daemon dir, killed at the end
    assert calls[-1] == ["daemon-kill"]
    assert (env.store / ".notmuch").exists()
    runs = cli.read_runs(cfg)
    assert runs[-1]["failed"] == [] and runs[-1]["changed"] == 2

    # second run: lei up only, nothing new
    env.log.unlink()
    assert sync.sync(cfg) == 0
    calls = lei_calls(env)
    # created just now, so the long lookback isn't due yet
    ups = sorted(c for c in calls if c[0] in ("q", "up"))
    assert ups == [["up", "--remote-fudge-time=1.day", f"{env.store}/ours-c2"],
                   ["up", "--remote-fudge-time=1.day", f"{env.store}/topic-glymur"]]
    # lookbackEvery later, ours-c2 (which has a lookback) asks for 10 years
    old = time.time() - 7 * 3600
    os.utime(sync.deep_path(cfg, "ours-c2"), (old, old))
    env.log.unlink()
    assert sync.sync(cfg) == 0
    ups = sorted((c for c in lei_calls(env) if c[0] == "up"), key=lambda c: c[-1])
    assert ups[0] == ["up", "--remote-fudge-time=10.years", f"{env.store}/ours-c2"]
    assert ups[1][1] == "--remote-fudge-time=1.day"
    assert time.time() - sync.deep_path(cfg, "ours-c2").stat().st_mtime < 60
    assert cli.read_runs(cfg)[-1]["changed"] == 0

    # a new message arrives on lore
    (env.mail / "c.eml").write_text(msg("reply@q", "Konrad Dybcio <konrad@q>",
                                        "Re: Glymur USB Gen2 fails", time.time() - 60,
                                        "m:root@x", reply_to="root@x"))
    assert sync.sync(cfg) == 0
    assert cli.read_runs(cfg)[-1]["changed"] == 1

    # the query changes: forget + q again
    env.raw["searches"]["topic-glymur"]["query"] = "s:glymur AND d:2026-10-20.."
    env.cfgpath.write_text(json.dumps(env.raw))
    env.log.unlink()
    cfg = config.load()
    assert sync.sync(cfg) == 0
    calls = lei_calls(env)
    assert ["forget-search", f"{env.store}/topic-glymur"] in calls
    assert any(c[0] == "q" and c[-1] == "s:glymur AND d:2026-10-20.." for c in calls)


def test_network_failure_is_retried(env, monkeypatch):
    cfg = config.load()
    monkeypatch.setenv("FAKE_LEI_FAIL", "1")
    assert sync.sync(cfg) == 1
    assert cli.read_runs(cfg)[-1]["failed"] == ["ours-c2", "topic-glymur"]
    assert not sync.spec_path(cfg, "ours-c2").exists()
    monkeypatch.delenv("FAKE_LEI_FAIL")
    assert sync.sync(cfg) == 0
    assert sync.spec_path(cfg, "ours-c2").exists()


def test_removed_search_is_forgotten(env):
    cfg = config.load()
    assert sync.sync(cfg) == 0
    del env.raw["searches"]["topic-glymur"]
    env.cfgpath.write_text(json.dumps(env.raw))
    cfg = config.load()
    assert sync.sync(cfg) == 0
    assert ["forget-search", f"{env.store}/topic-glymur"] in lei_calls(env)
    assert not sync.spec_path(cfg, "topic-glymur").exists()
    assert (env.store / "topic-glymur").is_dir()  # data kept


def test_lock_prevents_overlap(env):
    import fcntl
    cfg = config.load()
    cfg.state_dir.mkdir(parents=True)
    with open(cfg.state_dir / "lock", "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        assert sync.sync(cfg) == 0
    assert not env.log.exists()  # lei never ran


def test_lore_new(env, capsys):
    cfg = config.load()
    sync.sync(cfg)
    (env.mail / "c.eml").write_text(msg("reply@q", "Konrad Dybcio <konrad@q>",
                                        "Re: Glymur USB Gen2 fails", time.time() - 60,
                                        "m:root@x", reply_to="root@x",
                                        list_id="linux-phy.lists.infradead.org"))
    sync.sync(cfg)
    capsys.readouterr()

    assert cli.main(["--json"]) == 0
    rows = [json.loads(l) for l in capsys.readouterr().out.splitlines()]
    assert [r["msgid"] for r in rows] == ["root@x", "glymur1@q", "reply@q"]
    assert rows[1]["list"] == "devicetree" and rows[1]["searches"] == ["topic-glymur"]
    assert rows[2]["list"] == "linux-phy"

    assert cli.main(["list", "--last-run", "--json"]) == 0
    rows = [json.loads(l) for l in capsys.readouterr().out.splitlines()]
    assert [r["msgid"] for r in rows] == ["reply@q"]

    assert cli.main(["replies", "--json"]) == 0
    rows = [json.loads(l) for l in capsys.readouterr().out.splitlines()]
    assert [r["msgid"] for r in rows] == ["reply@q"]  # not Burke's own root

    assert cli.main(["--threads-only-ours", "--json"]) == 0
    rows = [json.loads(l) for l in capsys.readouterr().out.splitlines()]
    assert [r["msgid"] for r in rows] == ["root@x", "reply@q"]

    assert cli.main(["--search", "topic-glymur"]) == 0
    out = capsys.readouterr().out
    assert "<glymur1@q>" in out and "root@x" not in out

    assert cli.main(["show", "<reply@q>"]) == 0
    assert "Subject: Re: Glymur USB Gen2 fails" in capsys.readouterr().out
    assert cli.main(["show", "https://lore.kernel.org/all/root@x/", "--thread"]) == 0
    out = capsys.readouterr().out
    assert "Message-ID: <root@x>" in out and "Message-ID: <reply@q>" in out
    assert cli.main(["show", "missing@x"]) == 1

    # a run that added nothing
    sync.sync(cfg)
    capsys.readouterr()
    assert cli.main(["--last-run"]) == 0
    assert "(no messages)" in capsys.readouterr().out

    assert cli.main(["status"]) == 0
    out = capsys.readouterr().out
    assert "3 messages" in out and "ours-c2 (ours)" in out


def test_check_prints_commands(env, capsys):
    assert sync.main(["--check"]) == 0
    out = capsys.readouterr().out
    assert "lei q --only https://lore.kernel.org/all/" in out
    assert "--threads -o maildir:" in out


def test_missing_config(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("LORE_WATCH_CONFIG", str(tmp_path / "nope.json"))
    assert cli.main([]) == 2
    assert "not set up" in capsys.readouterr().err


def test_search_files_merge(tmp_path):
    extra = tmp_path / "searches.json"
    extra.write_text(json.dumps({
        "mine": {"query": "f:me@example.org", "threads": True, "ours": True},
        "shared": {"query": "s:override"},
    }))
    raw = {
        "dir": str(tmp_path / "lore"),
        "stateDir": str(tmp_path / "state"),
        "notmuchConfig": str(tmp_path / "nm"),
        "searches": {"shared": {"query": "s:module"}, "other": {"query": "s:x"}},
        "searchFiles": [str(extra), str(tmp_path / "missing.json")],
    }
    cfgfile = tmp_path / "config.json"
    cfgfile.write_text(json.dumps(raw))
    cfg = config.load(cfgfile)
    assert sorted(cfg.searches) == ["mine", "other", "shared"]
    assert cfg.searches["shared"].query == "s:override"
    assert cfg.ours == ["mine"]


def test_search_file_bad_json(tmp_path):
    bad = tmp_path / "searches.json"
    bad.write_text("{nope")
    cfgfile = tmp_path / "config.json"
    cfgfile.write_text(json.dumps({
        "dir": "d", "stateDir": "s", "notmuchConfig": "n", "searches": {},
        "searchFiles": [str(bad)],
    }))
    with pytest.raises(config.ConfigError):
        config.load(cfgfile)
