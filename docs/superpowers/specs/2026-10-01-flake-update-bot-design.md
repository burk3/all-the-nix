# Weekly flake update bot, Hydra, and juicy-j as a substituter

Status: draft for review. Nothing in this document is implemented except the
"Store upkeep" section.

## Goal

Every week, without my involvement, juicy-j updates `flake.lock`, opens a PR,
builds the juicy-j and freddie-kane system closures in Hydra, reports the result
on the PR, and lets Claude Code attempt a fix when the build fails.

After I merge that PR, on freddie-kane:

```sh
cd src/all-the-nix; git co master; git pull
nh os switch . --dry
```

**Acceptance test:** the dry run lists paths to fetch from juicy-j and nothing
to build.

## Current state (checked 2026-10-01)

- `systems/x86_64-linux/juicy-j/hydra.nix` exists but its import is commented
  out. Hydra, PostgreSQL and Caddy are inactive on juicy-j.
- It was disabled because a `localhost` entry in `nix.buildMachines` leaked into
  `/etc/nix/machines` and broke interactive `nix build`.
- `flake.nix` already exposes `hydraJobs.nixos.<host>` for all four NixOS hosts.
- juicy-j is not a substituter for anything. freddie-kane only uses it as a
  remote builder (`t11s.remotebuild`), as user `remotebuild` with root's key
  `/root/.ssh/remotebuild`.
- `t11s.internalCA` already makes every host trust the SSH host CA system-wide
  and makes sshd trust the SSH user CA.
- freddie-kane's system closure includes burke's home-manager config, so a
  cached system closure covers the home too.
- The repo is public on GitHub (`burk3/all-the-nix`).
- nixpkgs' Hydra links against upstream Nix 2.34.8. The host runs Determinate
  Nix 3.22 (based on 2.35.1). `DeterminateSystems/hydra` is archived.

## Components

### 1. Hydra on juicy-j

File: `systems/x86_64-linux/juicy-j/hydra.nix`, re-imported from `default.nix`.

- **Own machines file.** Remove `nix.distributedBuilds` and `nix.buildMachines`
  from this file. Give Hydra a private machines file through
  `services.hydra.buildMachinesFiles` containing only the localhost entry.
  Interactive `nix build` never reads it. The old nixbuild.net builder and
  substituter lines are dropped: there are no aarch64 jobs, the key under
  `/root/.ssh` is unreadable by `hydra-queue-runner`, and the substituter would
  affect every interactive build on juicy-j.
- **Determinate evaluator.** New flake input
  `nix-eval-jobs` = `DeterminateSystems/nix-eval-jobs` from FlakeHub. It keeps
  its own pinned nix-src and does not follow `determinate/nix`: the fork is
  released a little behind Determinate Nix and does not evaluate against a newer
  nix-src, so the evaluator can be one release behind the daemon. Hydra is
  overridden:
  `services.hydra.package = pkgs.hydra.override { nix-eval-jobs = <fork>; }`.
  Hydra calls `nix-eval-jobs` as an external binary, and every flag it passes is
  accepted by the fork. Fallback if this does not build or evaluate: drop the
  override (and then the parity check below decides whether the goal is still
  reachable).
- **Evaluator settings** in `services.hydra.extraConfig`:
  `evaluator_workers = 4`, `evaluator_max_memory_size = 8192`, and
  `allow_import_from_derivation = true` (stylix reads its colour scheme from a
  derivation).
- **Project and jobsets.** Project `all-the-nix` with two flake jobsets:

  | Jobset | Flake URI | Check interval | Keep |
  |---|---|---|---|
  | `master` | `git+https://github.com/burk3/all-the-nix?ref=master` | 300 s | 3 evals |
  | `flake-update` | `git+https://github.com/burk3/all-the-nix?ref=flake-update` | 60 s | 3 evals |

  Hydra polls both branches. There is no push trigger, because Hydra's push
  endpoint needs a logged-in user and polling a git remote does not. `git+https`
  avoids GitHub's unauthenticated API rate limit.

  Provisioned idempotently by a oneshot unit ordered after `hydra-server`, using
  Hydra's REST API. It logs in as an admin user whose password it regenerates on
  every run, so no secret is stored.
- Caddy vhost for `hydra.ts.t11s.net` stays as written.

What stays upstream: Hydra's own `nix flake metadata` call, the queue runner and
the Perl bindings. Builds are expected to go through `nix-daemon`, which is
`determinate-nixd`, because Hydra's services are not root.

### 2. juicy-j as a substituter over `ssh-ng`

No new service, secret, DNS name or signing key. juicy-j needs no change: the
`remotebuild` user from `t11s.remotebuild.serveBuilds` is the remote end.

Client side, in the client half of `modules/nixos/remotebuilder`, so the user
and key stay defined in one place. For each entry in `t11s.remotebuild.hosts`:

- Add a substituter:
  `ssh-ng://remotebuild@<host>?ssh-key=/root/.ssh/remotebuild&trusted=true`.
- `trusted=true` lets the daemon accept unsigned paths from that one store.
  freddie-kane already trusts juicy-j's store as its remote builder.
- SSH stores default to priority 0, so juicy-j is consulted before the HTTP
  caches.
- Add a `Host <host>` block with `ConnectTimeout 5` to
  `programs.ssh.extraConfig` so being off the tailnet does not hang.

How it runs: the Nix daemon on the client spawns OpenSSH's `ssh` as root with
`-i <ssh-key>`. Normal SSH config applies. The host is verified by its host
certificate through the system-wide `@cert-authority` entry from
`t11s.internalCA`, so no host key is pinned.

The remote-builder entry stays as the fallback for paths juicy-j has not built.

Not chosen:

- **harmonia (HTTP cache).** It adds a service, a signing key, a vhost and a DNS
  name, and clients cache "not found" answers for an hour. Worth revisiting if
  more clients appear or `ssh-ng` proves slow.
- **An SSH user certificate for root.** It would need unattended issuance from
  step-ca.

### 3. `flake-update-bot`

- `packages/flake-update-bot/default.nix`: the orchestrator, a
  `writeShellApplication` bundling `git`, `gh`, `curl`, `jq`, `nix` and Claude
  Code.
- `modules/nixos/flake-update-bot/default.nix`: `options.t11s.flakeUpdateBot`
  (`enable`, `repo`, `hosts`, `schedule`, `maxFixAttempts`), a systemd
  service with `User=burke`, and its timer. Secrets reach the service through
  `LoadCredential`, the way `monitoring.nix` already passes the Pushover keys.
- Enabled on juicy-j with `hosts = [ "juicy-j" "freddie-kane" ]`.

The bot works in its own clone at `~/.local/state/flake-update-bot/repo`, never
in `~/src/all-the-nix`.

### 4. `t11s-cached-system` (eval-free switch)

A small package that prints the store path Hydra built for a host at the commit
checked out in the current directory:

```sh
nh os switch "$(t11s-cached-system)" --dry
```

It queries the `master` jobset, requires a finished, successful build of
`nixos.<hostname>` whose evaluation is for `HEAD`, and exits non-zero otherwise
so the caller falls back to `nh os switch .`. Installed on freddie-kane.

### 5. Store upkeep (done, uncommitted)

- juicy-j: `nix.gc` Sun 03:00 `--delete-older-than 30d`; `nix.optimise`
  Sun 05:00.
- `burke@juicy-j`: home-manager `nix.gc` Sun 02:30 `--delete-older-than 30d`,
  for the profiles under `~/.local/state/nix/profiles`.
- determinate-nixd's own pressure-driven GC stays enabled.

## Weekly run

Timer: Saturday 04:00, `Persistent=true`. Clear of the Sunday GC window.

1. Fetch `origin`. Reset branch `flake-update` to `origin/master`.
2. `nix flake update`. If `flake.lock` is unchanged, exit 0 silently.
3. Close any open bot PR with a "superseded" comment.
4. Commit (`flake update YYYY-MM-DD`, input changes in the body), force-push
   `flake-update` over HTTPS, open a new PR against `master`.
5. Poll Hydra until an evaluation for the pushed commit exists (45 minute
   timeout), then until the gating jobs (`nixos.<host>` for each configured
   host) finish (6 hour timeout). Hydra picks the push up by polling the branch.
6. All gating jobs succeeded: comment with links to the Hydra builds and the
   output paths. Send a Pushover notification. Done.
7. Otherwise: comment with each failing job, its Hydra link and a log tail (or
   the evaluation error), then enter the fix loop. The log tail comes from
   re-running the failed derivation locally with `nix build`, which reruns only
   the failure because everything else is already in the store.

`hydraJobs` keeps building all four hosts. Only the configured hosts gate.

## Fix loop

Up to `maxFixAttempts` (default 3). Each attempt:

1. Run `claude -p` in the bot's clone, 60 minute timeout, with the failing jobs
   and log tails in the prompt. Auth through `CLAUDE_CODE_OAUTH_TOKEN`.
2. Allowed tools: read, edit and write files; `nix`; `git add`, `git commit`,
   `git diff`, `git status`, `git log`. No `git push`, no `gh`.
3. The prompt requires: a minimal fix; verification with a local
   `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` for each
   failing host; a local commit; and a short summary written to a file outside
   the repo. Pinning a single input back to its previous revision is allowed if
   the summary says why.
4. If Claude produced no commit, the attempt counts as failed.
5. The orchestrator pushes, re-triggers Hydra, and waits as in step 5 above.
6. Success: comment with Claude's summary and the Hydra links, notify, stop.
7. Failure: comment with the new failure and continue to the next attempt.

After the last failed attempt: comment that the bot gave up, notify, and leave
the PR open. The bot never merges.

Claude's local builds populate the store, so Hydra's rebuild is mostly cache
hits.

**Containment is soft.** Claude runs as burke, and `nix` can execute arbitrary
code, so the tool allowlist is a guardrail and not a sandbox. This was the
chosen trade-off (run as burke, subscription token) over a dedicated user.

## After merge

The `master` jobset notices the merge within 5 minutes and builds it. If master
did not move during the week, this is entirely cache hits from the PR build.
Hydra's GC roots (3 evaluations per jobset) keep the closure alive through the
weekly GC.

## Secrets and manual steps (mine to do)

| Secret | Purpose |
|---|---|
| `flake-update-bot-gh-token.age` | Fine-grained PAT, this repo only: Contents RW, Pull requests RW |
| `claude-oauth-token.age` | Output of `claude setup-token` |

- Recipients: burke's keys plus the juicy-j host key.
- Existing Pushover secrets are reused.
- I run the system switches on both hosts.

## Milestones

Each one is verified before the next starts.

1. **Hydra up with the Determinate evaluator; `master` green.** Verify
   interactive `nix build` still works on juicy-j. Verify parity: Hydra's
   `drvPath` for `nixos.freddie-kane` equals
   `nix eval .#nixosConfigurations.freddie-kane.config.system.build.toplevel.drvPath`
   run with Determinate Nix on the same commit.
2. **Substituter.** freddie-kane switched with the `ssh-ng` substituter. Verify
   the acceptance test against current master, and that a dry run off the
   tailnet falls through to the public caches within a few seconds.
3. **`t11s-cached-system`.** Verify `nh os switch "$(t11s-cached-system)" --dry`
   on freddie-kane does no evaluation and no building.
4. **Bot, success path.** Start the service by hand; verify branch, PR, Hydra
   build and comment.
5. **Bot, failure path.** Point the bot at a branch with a deliberately broken
   commit (branch override env var); verify failure comment, Claude fix, push,
   rebuild and success comment. Then verify the give-up path with
   `maxFixAttempts = 0`.

## Unverified assumptions

To be settled in milestone 1 unless noted.

- Hydra's test suite passes with the Determinate `nix-eval-jobs` fork, and the
  fork's JSON output is what Hydra's evaluator script expects. (The fork itself
  builds: checked 2026-10-01.)
- An evaluator one Determinate release behind the daemon still produces the
  same derivations. Covered by the parity check.
- The fork honours `lazy-trees` and `eval-cores` from `/etc/nix/nix.conf`.
- Hydra and Determinate Nix produce identical derivations for this flake when
  one fetches `git+https:` and the other evaluates a local checkout.
- The Claude Code tool allowlist syntax and `dontAsk` permission mode behave as
  the orchestrator expects in headless mode. Exercised in milestone 5.
- That Nix's `ssh-ng` store shells out to OpenSSH, and that juicy-j's host
  certificate verifies, was checked on juicy-j only, as burke. Expected to hold
  for the daemon on freddie-kane (same modules); confirmed in milestone 2.
- With the substituter unreachable, Nix warns and moves on to the other
  substituters instead of failing.
- `ssh-ng` substitution is fast enough for a weekly closure. Not measured.

## Costs accepted

- Hydra is built locally on juicy-j (no cache.nixos.org hit because of the
  override), most weeks.
- PostgreSQL and Hydra are two more services on a workstation.
- One more flake input.

## Out of scope

- Auto-merge.
- Hydra's `githubpulls` / `GithubStatus` plugins (PR checks instead of comments).
- Caching `homeConfigurations` for standalone `nh home switch`.
- aarch64 hosts.

## Defaults I chose that were not explicitly confirmed

- The substituter is wired into `modules/nixos/remotebuilder` for every
  `t11s.remotebuild.hosts` entry, not set on freddie-kane alone.
- Fixed branch `flake-update` with a new PR each week, older PR closed.
- Saturday 04:00 schedule, 3 fix attempts, 60 minute Claude timeout, 6 hour
  build timeout.
- 30 day GC retention.
- `t11s-cached-system` included in the first version.
