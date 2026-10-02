# flake-update-bot

`t11s.flakeUpdateBot` runs `pkgs.t11s.flake-update-bot` weekly on the host that also runs Hydra (juicy-j). The orchestrator is `packages/flake-update-bot/flake-update-bot.sh`; its Hydra logic is covered by `bash packages/flake-update-bot/tests.sh`.

- It works in its own clone at `~/.local/state/flake-update-bot/repo`, on branch `flake-update`, and never merges.
- Hydra is the gate: the bot pushes, then polls Hydra's JSON API for the evaluation of that commit. Hydra polls the branch itself (jobsets are declared in `systems/x86_64-linux/juicy-j/hydra.nix`).
- On failure it runs headless `claude` with a tool allowlist and its own `CLAUDE_CONFIG_DIR`. Claude never gets the GitHub token; the orchestrator pushes.
- It runs as the main user, so the allowlist is a guardrail, not a sandbox.
- Manual run: `sudo systemctl start flake-update-bot`, then `journalctl -fu flake-update-bot`.
- To test against an existing `flake-update` branch without updating the lock, set `FUB_SKIP_UPDATE=1` through a runtime drop-in.
