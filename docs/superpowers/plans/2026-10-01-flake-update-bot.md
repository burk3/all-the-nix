# Flake Update Bot, Hydra and ssh-ng Substituter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** juicy-j updates `flake.lock` weekly, opens a PR, gates it on Hydra builds of the juicy-j and freddie-kane closures, lets Claude Code attempt fixes, and serves the results to freddie-kane so `nh os switch . --dry` there has nothing to build.

**Architecture:** Hydra runs on juicy-j with its own machines file and Determinate's `nix-eval-jobs`, polling two git branches (`master`, `flake-update`). freddie-kane substitutes from juicy-j over `ssh-ng` using the existing `remotebuild` identity. A bash orchestrator run by a systemd timer does the git/GitHub work, reads Hydra's JSON API, and shells out to headless `claude` on failure.

**Tech Stack:** NixOS modules (snowfall-lib, namespace `t11s`), Hydra, Determinate Nix, agenix, bash + `jq` + `gh` + `curl`, Claude Code CLI.

**Spec:** `docs/superpowers/specs/2026-10-01-flake-update-bot-design.md`

---

## Ground rules for this plan

- **Who runs what.** Steps marked **USER** are for Burke: system builds and switches, creating secrets, anything interactive, and pushes to GitHub. Steps marked **AGENT** are safe for the executing agent: file edits, formatting, `nix eval`, small package builds, local commits. Do not run `nh os switch` or `nixos-rebuild` as the agent.
- **`lazy-trees` gotcha.** A new file is invisible to Nix until it is `git add`-ed. Every task that creates a file has an explicit `git add` step before the first `nix` command.
- **After every Nix edit** run `nix fmt` and `statix check` from the repo root and fix what they report.
- **Commits** end with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Work happens on branch `hydra-flake-update-bot`**, not on `master`. The bot's own branch is `flake-update`; do not confuse them.
- **Stop conditions.** Where a step says STOP, do not improvise a workaround. Report what happened and wait.

## Facts this plan relies on (verified 2026-10-01 against the pinned inputs)

- nixpkgs' Hydra runs `nix-eval-jobs` from `PATH` and accepts it as an `override` argument.
- With no machines file Hydra builds on localhost; `services.hydra.buildMachinesFiles` replaces the default `/etc/nix/machines`.
- Hydra's `POST` endpoints need a logged-in user and a `Referer` header; reads are anonymous. This plan only uses authenticated calls for provisioning.
- `GET /jobset/<p>/<j>/evals` lists only evaluations that created new builds. Each has `id`, `flake` (the locked flake ref, containing the commit) and `builds` (ids).
- `GET /build/<id>` has `job`, `finished`, `buildstatus` (0 is success), `drvpath`, `buildoutputs.out.path`.
- `GET /jobset/<p>/<j>` has `lastcheckedtime`, `errormsg`, `errortime`, `fetcherrormsg`.
- Hydra config keys: `evaluator_workers`, `evaluator_max_memory_size`, `allow_import_from_derivation`.
- Nix's `ssh-ng` store runs OpenSSH's `ssh`, honours `NIX_SSHOPTS`, and has a `trusted` store setting.
- `claude --bare` cannot use an OAuth token, so the bot isolates Claude with `CLAUDE_CONFIG_DIR` instead.

## Deviations from the spec (the spec has been updated to match)

- Hydra's machines file has only the localhost entry. The old nixbuild.net builder and substituter lines are dropped: there are no aarch64 jobs, the key under `/root/.ssh` is unreadable by `hydra-queue-runner`, and the substituter would affect every interactive build on juicy-j.
- Jobsets use `git+https://github.com/burk3/all-the-nix?ref=<branch>` and are polled (master every 300 s, flake-update every 60 s). No push trigger, so the bot needs no Hydra credentials.
- Provisioning needs no stored secret: the oneshot regenerates a throwaway admin password on every run.
- `allow_import_from_derivation = true` in Hydra, because stylix reads its colour scheme from a derivation.
- Failure logs come from re-running the failed derivation locally with `nix build`, not from Hydra's log pages.
- No `claudePackage` option; the package uses `pkgs.unstable.claude-code`.

## File structure

| File | Action | Responsibility |
|---|---|---|
| `flake.nix` | modify | add the `nix-eval-jobs` input |
| `systems/x86_64-linux/juicy-j/hydra.nix` | rewrite | Hydra, its machines file, evaluator override, project/jobset provisioning, Caddy vhost |
| `systems/x86_64-linux/juicy-j/default.nix` | modify | import `hydra.nix`; enable the bot (GC edits already present) |
| `modules/nixos/remotebuilder/default.nix` | modify | add the `ssh-ng` substituter and SSH connect timeout for clients |
| `modules/nixos/remotebuilder/CLAUDE.md` | modify | document the substituter |
| `packages/t11s-cached-system/default.nix` | create | package for the helper |
| `packages/t11s-cached-system/t11s-cached-system.sh` | create | resolve Hydra's store path for `HEAD` |
| `systems/x86_64-linux/freddie-kane/default.nix` | modify | install the helper |
| `packages/flake-update-bot/default.nix` | create | package for the orchestrator |
| `packages/flake-update-bot/flake-update-bot.sh` | create | the orchestrator |
| `packages/flake-update-bot/tests.sh` | create | tests for the orchestrator's Hydra logic |
| `modules/nixos/flake-update-bot/default.nix` | create | `t11s.flakeUpdateBot` options, service, timer, secrets |
| `modules/nixos/flake-update-bot/CLAUDE.md` | create | notes for future work on the bot |
| `secrets.nix` | modify | recipients for two new secrets |
| `secrets/flake-update-bot-gh-token.age`, `secrets/claude-oauth-token.age` | create (USER) | secrets |
| `systems/x86_64-linux/juicy-j/CLAUDE.md` | modify | document Hydra and the bot |

---

### Task 0: Branch and commit the work that already exists

The working tree already has the GC/optimise edits and the spec, uncommitted, on `master`.

**Files:**
- Existing changes: `systems/x86_64-linux/juicy-j/default.nix`, `homes/x86_64-linux/burke@juicy-j/default.nix`, `docs/superpowers/`

- [ ] **Step 1 (AGENT): Create the branch**

```bash
cd /home/burke/src/all-the-nix
git checkout -b hydra-flake-update-bot
git status --short
```

Expected: the two modified `.nix` files and untracked `docs/`.

- [ ] **Step 2 (AGENT): Commit the GC and optimise change**

```bash
git add systems/x86_64-linux/juicy-j/default.nix 'homes/x86_64-linux/burke@juicy-j/default.nix'
git commit -m "juicy-j: weekly nix gc and store optimise

determinate-nixd only collects under disk pressure and never expires
generations. Add scheduled GC for the system and for burke's profiles,
then optimise.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3 (AGENT): Commit the spec and this plan**

```bash
git add docs/superpowers
git commit -m "docs: flake-update-bot design and implementation plan

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: Add Determinate's `nix-eval-jobs` as a flake input

> **Outcome (2026-10-01):** done, with one change. `determinate` updated to 3.23.0 while the fork is at 3.22.5, and the fork does not evaluate against nix-src 3.23.0 (`attribute 'bdwgc' missing`). The `inputs.nix.follows` line was removed, so the evaluator uses its own pinned nix-src 3.22.5. It builds (two small derivations; the Nix libraries are substituted). The steps below are kept as originally written.

**Files:**
- Modify: `flake.nix` (the `inputs` block, directly after the `determinate.url` line)
- Modify: `flake.lock` (generated)

- [ ] **Step 1 (AGENT): Add the input**

In `flake.nix`, find:

```nix
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
```

and insert directly below it:

```nix
    # Hydra's evaluator, built against Determinate Nix so Hydra evaluates the
    # way the CLI does (lazy trees included). Follows determinate's nix so the
    # evaluator and the daemon are the same version.
    nix-eval-jobs = {
      url = "https://flakehub.com/f/DeterminateSystems/nix-eval-jobs/*";
      inputs.nix.follows = "determinate/nix";
    };
```

- [ ] **Step 2 (AGENT): Lock it, and bring `determinate` to the matching release**

The fork is released in step with Determinate Nix. The lock currently has determinate 3.22.4 and the fork's latest is 3.22.5, so update `determinate` too.

```bash
nix flake update determinate nix-eval-jobs
jq -r '.nodes.determinate.locked.url, .nodes."nix-eval-jobs".locked.url' flake.lock
```

Expected: two FlakeHub URLs whose version components match in major.minor.patch (for example `determinate/3.22.5/` and `nix-eval-jobs/3.22.5%2Brepublish.1/`). If they differ, note both versions in the commit message and continue; Step 4 is the real test.

- [ ] **Step 3 (AGENT): Check the package evaluates**

```bash
nix fmt
nix eval --raw --impure --expr \
  '(builtins.getFlake (toString ./.)).inputs.nix-eval-jobs.packages.x86_64-linux.default.name'
```

Expected: a name starting with `nix-eval-jobs-`.

- [ ] **Step 4 (USER): Build the evaluator**

```bash
nix build --no-link --print-out-paths --impure --expr \
  '(builtins.getFlake (toString ./.)).inputs.nix-eval-jobs.packages.x86_64-linux.default'
```

Expected: a store path. If it fails to compile, remove the `inputs.nix.follows = "determinate/nix";` line, run `nix flake update nix-eval-jobs`, and build again. If that also fails, STOP.

- [ ] **Step 5 (AGENT): Commit**

```bash
git add flake.nix flake.lock
git commit -m "flake: add Determinate nix-eval-jobs for Hydra

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Re-enable Hydra with its own machines file and the Determinate evaluator

**Files:**
- Rewrite: `systems/x86_64-linux/juicy-j/hydra.nix`
- Modify: `systems/x86_64-linux/juicy-j/default.nix` (the `imports` list)

- [ ] **Step 1 (AGENT): Replace `systems/x86_64-linux/juicy-j/hydra.nix` with**

```nix
{
  pkgs,
  inputs,
  ...
}:
let
  # Hydra reads only this file. Keeping the localhost builder out of
  # nix.buildMachines means /etc/nix/machines is never written, so interactive
  # `nix build` does not try to SSH into this machine. i686-linux is listed
  # because Steam on other hosts pulls in 32-bit derivations.
  machines = pkgs.writeText "hydra-machines" ''
    localhost x86_64-linux,i686-linux - 16 1 kvm,big-parallel,nixos-test,benchmark - -
  '';
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
  };

  services.hydra = {
    enable = true;
    listenHost = "127.0.0.1";
    port = 3001;
    hydraURL = "https://hydra.ts.t11s.net";
    notificationSender = "hydra@juicy-j.lan";
    useSubstitutes = true;
    buildMachinesFiles = [ "${machines}" ];
    # nixpkgs' Hydra links upstream Nix, but it runs nix-eval-jobs as a
    # separate program. Swapping that for Determinate's build makes Hydra
    # produce the same derivations as `nh os switch` on the other hosts, which
    # is what lets them substitute Hydra's builds.
    package = pkgs.hydra.override {
      nix-eval-jobs = inputs.nix-eval-jobs.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };
    extraConfig = ''
      evaluator_workers = 4
      evaluator_max_memory_size = 8192
      # stylix reads its colour scheme out of a derivation
      allow_import_from_derivation = true
    '';
  };

  services.caddy = {
    enable = true;
    globalConfig = ''
      acme_ca https://turing.lan/acme/acme/directory
    '';
    virtualHosts."hydra.ts.t11s.net, hydra.lan".extraConfig = ''
      tls {
        issuer acme {
          disable_http_challenge
        }
      }
      reverse_proxy 127.0.0.1:3001
    '';
  };

  networking.firewall.allowedTCPPorts = [ 443 ];
}
```

- [ ] **Step 2 (AGENT): Import it**

In `systems/x86_64-linux/juicy-j/default.nix` replace

```nix
    # ./hydra.nix  # disabled: localhost remote builder kept breaking interactive nix build
```

with

```nix
    ./hydra.nix
```

- [ ] **Step 3 (AGENT): Check the configuration evaluates the way it should**

```bash
nix fmt && statix check
nix eval --raw .#nixosConfigurations.juicy-j.config.services.hydra.package.name; echo
nix eval --json .#nixosConfigurations.juicy-j.config.nix.buildMachines
nix eval --json .#nixosConfigurations.juicy-j.config.nix.distributedBuilds
nix eval --raw .#nixosConfigurations.juicy-j.config.systemd.services.hydra-queue-runner.environment.NIX_REMOTE_SYSTEMS; echo
```

Expected, in order: a name starting with `hydra-`; `[]`; `false`; a store path ending in `-hydra-machines`.

- [ ] **Step 4 (AGENT): Commit**

```bash
git add systems/x86_64-linux/juicy-j/hydra.nix systems/x86_64-linux/juicy-j/default.nix
git commit -m "juicy-j: re-enable hydra with a private machines file

The localhost builder now lives in a file only Hydra reads, so
/etc/nix/machines is not written and interactive builds are unaffected.
Hydra evaluates with Determinate's nix-eval-jobs.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5 (USER): Build and switch juicy-j**

```bash
nh os switch .
```

This compiles Hydra locally and runs its test suite, so it takes a while. If Hydra's build or tests fail, STOP and report the failing output: the choice between disabling Hydra's tests and dropping the evaluator override is Burke's.

- [ ] **Step 6 (AGENT): Verify Hydra is up and interactive builds are unaffected**

```bash
systemctl is-active postgresql hydra-server hydra-evaluator hydra-queue-runner caddy
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3001/
test ! -e /etc/nix/machines && echo "no global machines file"
nix config show builders
nix build --no-link --impure --expr \
  'with import <nixpkgs> {}; runCommand "fub-interactive-${toString builtins.currentTime}" {} "echo ok > $out"' \
  && echo "interactive build ok"
```

Expected: five `active` lines; `200`; `no global machines file`; an empty line for `builders`; `interactive build ok` with no SSH attempt in the output.

---

### Task 3: Provision the project and jobsets, get `master` green, check evaluator parity

**Files:**
- Modify: `systems/x86_64-linux/juicy-j/hydra.nix`

- [ ] **Step 1 (AGENT): Add the provisioning unit**

In `hydra.nix`, change the function arguments to

```nix
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
```

extend the `let` block so it reads

```nix
let
  # Hydra reads only this file. Keeping the localhost builder out of
  # nix.buildMachines means /etc/nix/machines is never written, so interactive
  # `nix build` does not try to SSH into this machine. i686-linux is listed
  # because Steam on other hosts pulls in 32-bit derivations.
  machines = pkgs.writeText "hydra-machines" ''
    localhost x86_64-linux,i686-linux - 16 1 kvm,big-parallel,nixos-test,benchmark - -
  '';

  project = "all-the-nix";
  repo = "https://github.com/burk3/all-the-nix";
  # Jobset name = git branch. Value = how often Hydra polls it, in seconds.
  jobsets = {
    master = 300;
    flake-update = 60;
  };

  projectJson = pkgs.writeText "hydra-project.json" (
    builtins.toJSON {
      name = project;
      displayname = project;
      description = "NixOS hosts from ${repo}";
      homepage = repo;
      enabled = "1";
      visible = "1";
    }
  );
  jobsetJson =
    name: checkinterval:
    pkgs.writeText "hydra-jobset-${name}.json" (
      builtins.toJSON {
        inherit name;
        type = 1; # flake
        flake = "git+${repo}?ref=${name}";
        description = "hydraJobs of the ${name} branch";
        enabled = "1";
        visible = "1";
        checkinterval = toString checkinterval;
        keepnr = "3";
        schedulingshares = "100";
        emailoverride = "";
      }
    );
in
```

and add this attribute to the module body, after `services.hydra`:

```nix
  # The project and jobsets are declared above, not clicked together in the
  # web UI. This unit re-applies them on every switch through Hydra's REST
  # API, logging in as an admin user whose password is regenerated on each run
  # and never stored.
  systemd.services.hydra-provision = {
    description = "Declare the ${project} Hydra project and jobsets";
    wantedBy = [ "multi-user.target" ];
    requires = [ "hydra-server.service" ];
    after = [ "hydra-server.service" ];
    path = [
      config.services.hydra.package
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
    ];
    environment = {
      HYDRA_DBI = config.services.hydra.dbi;
      HYDRA_CONFIG = "/var/lib/hydra/hydra.conf";
      HYDRA_DATA = "/var/lib/hydra";
      PGPASSFILE = "/var/lib/hydra/pgpass";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "hydra";
      PrivateTmp = true;
    };
    script = ''
      url=http://127.0.0.1:${toString config.services.hydra.port}
      password=$(head -c 24 /dev/urandom | base64)
      hydra-create-user provision --role admin --password "$password"

      cd "$(mktemp -d)"
      api() {
        curl -fsS --referer "$url" \
          -H 'Accept: application/json' -H 'Content-Type: application/json' "$@"
      }
      jq -n --arg p "$password" '{username: "provision", password: $p}' |
        api --retry 30 --retry-connrefused --retry-delay 2 \
          -X POST -d @- -c cookie "$url/login" >/dev/null
      api -b cookie -X PUT -d @${projectJson} "$url/project/${project}" >/dev/null
      ${lib.concatStrings (
        lib.mapAttrsToList (name: checkinterval: ''
          api -b cookie -X PUT -d @${jobsetJson name checkinterval} "$url/jobset/${project}/${name}" >/dev/null
        '') jobsets
      )}
    '';
  };
```

- [ ] **Step 2 (AGENT): Check it evaluates and commit**

```bash
nix fmt && statix check
nix eval --raw .#nixosConfigurations.juicy-j.config.systemd.services.hydra-provision.script
```

Expected: a script containing two `PUT ... /jobset/all-the-nix/...` lines, one for `flake-update` and one for `master`.

```bash
git add systems/x86_64-linux/juicy-j/hydra.nix
git commit -m "juicy-j: declare hydra project and jobsets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3 (USER): Switch juicy-j**

```bash
nh os switch .
```

- [ ] **Step 4 (AGENT): Verify provisioning**

```bash
systemctl is-active hydra-provision
for j in master flake-update; do
  curl -fsS -H 'Accept: application/json' "http://127.0.0.1:3001/jobset/all-the-nix/$j" |
    jq -c '{name, flake, checkinterval, enabled}'
done
```

Expected: `active`, then two objects with `flake` set to `git+https://github.com/burk3/all-the-nix?ref=<name>`, `checkinterval` 300 and 60, `enabled` 1. If `hydra-provision` failed, read `journalctl -u hydra-provision -n 50` and fix the request it names.

- [ ] **Step 5 (AGENT): Wait for the first `master` evaluation**

`flake-update` will show a fetch error until the bot first pushes that branch. That is expected.

```bash
journalctl -u hydra-evaluator -n 40 --no-pager
curl -fsS -H 'Accept: application/json' http://127.0.0.1:3001/jobset/all-the-nix/master |
  jq '{lastcheckedtime, errormsg, fetcherrormsg}'
curl -fsS -H 'Accept: application/json' http://127.0.0.1:3001/jobset/all-the-nix/master/evals |
  jq '.evals[0] | {id, flake, builds}'
```

Poll every minute or so, for up to 15 minutes. Expected: an evaluation whose `flake` ends in `&rev=<the commit of origin/master>` with four build ids. If `errormsg` is non-empty or no evaluation appears, STOP and report `errormsg` plus the evaluator journal: this is the "Hydra evaluates with the Determinate fork" assumption failing.

- [ ] **Step 6 (AGENT): Wait for the builds and record their status**

```bash
eval_id=$(curl -fsS -H 'Accept: application/json' \
  http://127.0.0.1:3001/jobset/all-the-nix/master/evals | jq '.evals[0].id')
for id in $(curl -fsS -H 'Accept: application/json' \
    http://127.0.0.1:3001/jobset/all-the-nix/master/evals | jq '.evals[0].builds[]'); do
  curl -fsS -H 'Accept: application/json' "http://127.0.0.1:3001/build/$id" |
    jq -r '"\(.job)\tfinished=\(.finished)\tstatus=\(.buildstatus)\t\(.drvpath)"'
done
echo "eval $eval_id"
```

Repeat until `nixos.juicy-j` and `nixos.freddie-kane` show `finished=1 status=0`. The other two hosts do not gate anything; report their status but do not fix them here. If either gating host fails, STOP and report: master does not build in Hydra.

- [ ] **Step 7 (AGENT): Check evaluator parity**

This is the assumption the whole cache goal rests on: Hydra's derivation for a host must equal the one the CLI computes.

Evaluate from a plain checkout of the same commit, the way freddie-kane will:

```bash
git fetch origin
git worktree add ../atn-master origin/master
for host in juicy-j freddie-kane; do
  echo "$host cli $(nix eval --raw \
    "../atn-master#nixosConfigurations.$host.config.system.build.toplevel.drvPath")"
done
git worktree remove ../atn-master
```

Compare each line with the `drvpath` Step 6 printed for `nixos.<host>`. Expected: identical for both hosts. If they differ, STOP and report both paths plus the output of `nix derivation show <cli-drv> | head -c 2000`. Do not continue: without parity nothing downstream meets the goal.

- [ ] **Step 8 (AGENT): Confirm Hydra roots its builds**

```bash
ls /nix/var/nix/gcroots/hydra | head
```

Expected: store path names, including the two system closures.

---

### Task 4: Make juicy-j a substituter for hosts that already build on it

**Files:**
- Modify: `modules/nixos/remotebuilder/default.nix` (the `# client stuff` section)
- Modify: `modules/nixos/remotebuilder/CLAUDE.md`

- [ ] **Step 1 (AGENT): Add the substituter and the SSH timeout**

In `modules/nixos/remotebuilder/default.nix`, find

```nix
      # client stuff
      nix.distributedBuilds = mkIfRemotes true;
      nix.settings.builders-use-substitutes = mkIfRemotes true;
```

and insert directly below it:

```nix
      # Also substitute from the builders, with the same user and key. Their
      # stores are unsigned, so `trusted=true` is what lets the daemon accept
      # paths from them; it is scoped to these stores only.
      nix.settings.substituters = mkIfRemotes (
        map (
          hostName: "ssh-ng://remotebuild@${hostName}?ssh-key=/root/.ssh/remotebuild&trusted=true"
        ) cfg.hosts
      );
      # Nix shells out to OpenSSH for builders and ssh-ng substituters. Without
      # a connect timeout an unreachable builder (laptop off the tailnet)
      # stalls every build.
      systemd.services.nix-daemon.environment.NIX_SSHOPTS = mkIfRemotes "-o ConnectTimeout=5";
```

- [ ] **Step 2 (AGENT): Check the result on a client and on the server**

```bash
nix fmt && statix check
nix eval --json .#nixosConfigurations.freddie-kane.config.nix.settings.substituters
nix eval --raw .#nixosConfigurations.freddie-kane.config.systemd.services.nix-daemon.environment.NIX_SSHOPTS; echo
nix eval --json .#nixosConfigurations.juicy-j.config.nix.settings.substituters
```

Expected: freddie-kane's list contains `ssh-ng://remotebuild@juicy-j.dab-ling.ts.net?ssh-key=/root/.ssh/remotebuild&trusted=true`; `-o ConnectTimeout=5`; juicy-j's list contains no `ssh-ng` entry.

- [ ] **Step 3 (AGENT): Document it**

Append to `modules/nixos/remotebuilder/CLAUDE.md`:

```markdown

Clients also **substitute** from each builder over `ssh-ng`, as the same `remotebuild` user with the same root key. The stores are unsigned, so the substituter URL carries `trusted=true`. `NIX_SSHOPTS` on the client's `nix-daemon` sets a 5 second connect timeout so an unreachable builder does not hang builds. On juicy-j, Hydra keeps the closures of `master` built, which is what makes `nh os switch` on a client fetch instead of build.
```

- [ ] **Step 4 (AGENT): Commit**

```bash
git add modules/nixos/remotebuilder
git commit -m "remotebuilder: substitute from builders over ssh-ng

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5 (USER): Get the branch onto freddie-kane and switch it**

On freddie-kane, in `~/src/all-the-nix`, fetch `hydra-flake-update-bot` (from GitHub or from the `juicy-j` remote), check it out, and run:

```bash
nh os switch .
```

- [ ] **Step 6 (USER): Verify the substituter from freddie-kane**

```bash
sudo nix store info --store 'ssh-ng://remotebuild@juicy-j.dab-ling.ts.net?ssh-key=/root/.ssh/remotebuild'
```

Expected: a `Store URL:` line and a version, with no host-key prompt.

- [ ] **Step 7 (USER): Run the acceptance test against master**

```bash
git fetch origin
git worktree add ../atn-master origin/master
cd ../atn-master
nh os switch . --dry
cd - && git worktree remove ../atn-master
```

Expected: paths "will be fetched" and no derivations "will be built". If derivations are listed to build, compare `nix eval --raw .#nixosConfigurations.freddie-kane.config.system.build.toplevel.drvPath` in that worktree with Hydra's `drvpath` from Task 3: a difference means parity does not hold on freddie-kane, and that is a STOP.

- [ ] **Step 8 (USER, optional): Off-tailnet behaviour**

This drops the eternal-terminal session to juicy-j while tailscale is down.

```bash
sudo tailscale down
time nh os switch . --dry
sudo tailscale up
```

Expected: a warning about the unreachable `ssh-ng` store, then the normal dry-run output, within a few seconds of the usual time.

---

### Task 5: `t11s-cached-system`, the evaluation-free switch helper

**Files:**
- Create: `packages/t11s-cached-system/t11s-cached-system.sh`
- Create: `packages/t11s-cached-system/default.nix`
- Modify: `systems/x86_64-linux/freddie-kane/default.nix` (the `environment.systemPackages` list)

- [ ] **Step 1 (AGENT): Create `packages/t11s-cached-system/t11s-cached-system.sh`**

````bash
# Print the store path Hydra built for a host at the commit checked out in the
# current directory, for: nh os switch "$(t11s-cached-system)"
# Exits non-zero when Hydra has no finished, successful build of that commit.

host=${1:-$(</proc/sys/kernel/hostname)}
url=${T11S_HYDRA_URL:-https://hydra.ts.t11s.net}
jobset=${T11S_HYDRA_JOBSET:-all-the-nix/master}

die() {
  echo "t11s-cached-system: $*" >&2
  exit 1
}

get() { curl -fsS -H 'Accept: application/json' "$url$1"; }

[[ -z $(git status --porcelain --untracked-files=no) ]] ||
  die "the working tree has uncommitted changes, so Hydra cannot have built it"
rev=$(git rev-parse HEAD)

# Hydra lists only evaluations that changed the set of builds, so a commit
# that leaves every system unchanged has no entry here.
eval_json=$(get "/jobset/$jobset/evals" |
  jq -c --arg rev "$rev" 'first(.evals[] | select((.flake // "") | contains($rev))) // empty')
[[ -n $eval_json ]] || die "Hydra has no evaluation of $rev in $jobset"

for id in $(jq -r '.builds[]' <<<"$eval_json"); do
  build=$(get "/build/$id")
  [[ $(jq -r .job <<<"$build") == "nixos.$host" ]] || continue
  [[ $(jq -r '(.finished == 1 or .finished == true) and .buildstatus == 0' <<<"$build") == true ]] ||
    die "build $id of nixos.$host is unfinished or failed: $url/build/$id"
  jq -r '.buildoutputs.out.path' <<<"$build"
  exit 0
done
die "the evaluation of $rev has no nixos.$host job"
````

- [ ] **Step 2 (AGENT): Create `packages/t11s-cached-system/default.nix`**

```nix
{
  writeShellApplication,
  git,
  curl,
  jq,
  ...
}:
writeShellApplication {
  name = "t11s-cached-system";
  runtimeInputs = [
    git
    curl
    jq
  ];
  text = builtins.readFile ./t11s-cached-system.sh;
  meta.description = "print the system closure Hydra built for the checked-out commit";
}
```

- [ ] **Step 3 (AGENT): Build it (this runs shellcheck)**

```bash
git add packages/t11s-cached-system
nix fmt && statix check
nix build --no-link --print-out-paths .#t11s-cached-system
```

Expected: a store path, no shellcheck findings.

- [ ] **Step 4 (AGENT): Test the failure path**

Run it in the development checkout, whose `HEAD` is a branch commit Hydra has never evaluated:

```bash
T11S_HYDRA_URL=http://127.0.0.1:3001 nix run .#t11s-cached-system -- freddie-kane; echo "exit=$?"
```

Expected: `t11s-cached-system: Hydra has no evaluation of <sha> in all-the-nix/master` and `exit=1`. If the tree has uncommitted changes the message is the "uncommitted changes" one instead; commit or stash and rerun.

- [ ] **Step 5 (AGENT): Test the success path**

```bash
bot=$PWD
git worktree add ../atn-master origin/master
cd ../atn-master
T11S_HYDRA_URL=http://127.0.0.1:3001 nix run "$bot#t11s-cached-system" -- freddie-kane; echo "exit=$?"
cd "$bot" && git worktree remove ../atn-master
```

Expected: a `/nix/store/...-nixos-system-freddie-kane-...` path and `exit=0`. It must be the `buildoutputs.out.path` of the `nixos.freddie-kane` build from Task 3 Step 6.

- [ ] **Step 6 (AGENT): Install it on freddie-kane**

In `systems/x86_64-linux/freddie-kane/default.nix` change

```nix
  environment.systemPackages = with pkgs; [
    dnsmasq
  ];
```

to

```nix
  environment.systemPackages = with pkgs; [
    dnsmasq
    t11s.t11s-cached-system
  ];
```

```bash
nix fmt && statix check
nix eval --json .#nixosConfigurations.freddie-kane.config.environment.systemPackages \
  --apply 'ps: builtins.any (p: (p.name or "") == "t11s-cached-system") ps'
```

Expected: `true`.

- [ ] **Step 7 (AGENT): Commit**

```bash
git add packages/t11s-cached-system systems/x86_64-linux/freddie-kane/default.nix
git commit -m "t11s-cached-system: resolve Hydra's closure for HEAD

For: nh os switch \"\$(t11s-cached-system)\"

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8 (USER): Verify on freddie-kane after its next switch**

Once this branch is switched on freddie-kane, from a clean checkout of `master`:

```bash
nh os switch "$(t11s-cached-system)" --dry
```

Expected: no evaluation phase, paths to fetch only.

---

### Task 6: The orchestrator package

> **Outcome (2026-10-01):** done, then revised after an independent review. The files in `packages/flake-update-bot/` are authoritative; the listings below are the original versions. Changes: Hydra being unreachable or timing out is reported as "no result" and does not start the fix loop; credentials are redacted from PR comments and a commit containing one is not pushed; the push goes to an explicit github.com URL with a host-scoped credential helper; Pushover keys are no longer passed as process arguments; the build timeout is 4 hours; shellcheck rule SC2016 is excluded in `default.nix`.

The Hydra-facing logic (`find_eval`, `gating_summary`, `wait_for_eval`, `success_report`) is tested with Hydra's API stubbed. The git, GitHub and Claude steps are exercised end to end in Tasks 8 and 9.

**Files:**
- Create: `packages/flake-update-bot/tests.sh`
- Create: `packages/flake-update-bot/flake-update-bot.sh`
- Create: `packages/flake-update-bot/default.nix`

- [ ] **Step 1 (AGENT): Write the tests, `packages/flake-update-bot/tests.sh`**

````bash
#!/usr/bin/env bash
# Tests for the pure parts of flake-update-bot.sh, with Hydra's API stubbed.
# Run: bash packages/flake-update-bot/tests.sh
set -euo pipefail
cd "$(dirname "$0")"

export FUB_REPO=example/repo FUB_HOSTS="juicy-j freddie-kane" FUB_LIB_ONLY=1
export FUB_POLL=0 FUB_EVAL_TIMEOUT=5
# shellcheck source=flake-update-bot.sh
source ./flake-update-bot.sh

fails=0
check() { # name, expected, actual
  if [[ $2 == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "  expected: $2"
    echo "  actual:   $3"
    fails=$((fails + 1))
  fi
}

REV=1111111111111111111111111111111111111111
EVALS_WITH_REV='{"evals":[{"id":7,"flake":"git+https://github.com/example/repo?ref=flake-update&rev='$REV'","builds":[70,71]},{"id":6,"flake":"git+https://github.com/example/repo?ref=flake-update&rev=0000","builds":[60]}]}'
EVALS_OLD_ONLY='{"evals":[{"id":6,"flake":"git+https://github.com/example/repo?ref=flake-update&rev=0000","builds":[60]}]}'

# --- find_eval -------------------------------------------------------------
EVALS=$EVALS_WITH_REV
hydra_get() { echo "$EVALS"; }
check "find_eval picks the eval for the revision" 7 "$(find_eval "$REV" | jq -r .id)"
EVALS=$EVALS_OLD_ONLY
check "find_eval prints nothing when no eval matches" "" "$(find_eval "$REV")"

# --- gating_summary --------------------------------------------------------
ok_j='{"id":70,"job":"nixos.juicy-j","finished":1,"buildstatus":0,"drvpath":"/nix/store/a.drv","buildoutputs":{"out":{"path":"/nix/store/a"}}}'
ok_f='{"id":71,"job":"nixos.freddie-kane","finished":1,"buildstatus":0,"drvpath":"/nix/store/b.drv","buildoutputs":{"out":{"path":"/nix/store/b"}}}'
bad_f='{"id":71,"job":"nixos.freddie-kane","finished":1,"buildstatus":2,"drvpath":"/nix/store/b.drv","buildoutputs":{}}'
run_f='{"id":71,"job":"nixos.freddie-kane","finished":0,"buildstatus":null,"drvpath":"/nix/store/b.drv","buildoutputs":{}}'
other='{"id":72,"job":"nixos.playground","finished":1,"buildstatus":1,"drvpath":"/nix/store/c.drv","buildoutputs":{}}'

s=$(gating_summary juicy-j freddie-kane <<<"[$ok_j,$ok_f,$other]")
check "all gating builds ok is success" success "$(jq -r .state <<<"$s")"
check "success lists output paths" "/nix/store/a /nix/store/b" "$(jq -r '[.ok[].out] | join(" ")' <<<"$s")"

s=$(gating_summary juicy-j freddie-kane <<<"[$ok_j,$bad_f]")
check "a failed gating build is failure" failure "$(jq -r .state <<<"$s")"
check "failure carries the drv path" "/nix/store/b.drv" "$(jq -r '.failed[0].drvpath' <<<"$s")"

s=$(gating_summary juicy-j freddie-kane <<<"[$ok_j,$run_f]")
check "an unfinished gating build is pending" pending "$(jq -r .state <<<"$s")"

s=$(gating_summary juicy-j freddie-kane <<<"[$ok_j]")
check "a gating job absent from the eval is failure" failure "$(jq -r .state <<<"$s")"
check "the absent job is reported as missing" "nixos.freddie-kane" "$(jq -r '.missing[0]' <<<"$s")"

s=$(gating_summary juicy-j <<<"[$ok_j,$other]")
check "a failing non-gating job does not gate" success "$(jq -r .state <<<"$s")"

# --- wait_for_eval ---------------------------------------------------------
JOBSET='{}'
hydra_get() {
  case $1 in
    */evals) echo "$EVALS" ;;
    *) echo "$JOBSET" ;;
  esac
}

EVALS=$EVALS_WITH_REV
wait_for_eval "$REV" 100 && rc=0 || rc=$?
check "wait_for_eval returns the eval for the revision" "0 7" "$rc $(jq -r .id <<<"$EVAL_JSON")"

EVALS=$EVALS_OLD_ONLY
JOBSET='{"lastcheckedtime":200,"errortime":200,"errormsg":"error: attribute missing","fetcherrormsg":null}'
wait_for_eval "$REV" 100 && rc=0 || rc=$?
check "an evaluation error after the push fails fast" "1 error: attribute missing" "$rc $EVAL_ERROR"

JOBSET='{"lastcheckedtime":50,"errortime":50,"errormsg":"stale error","fetcherrormsg":null}'
wait_for_eval "$REV" 100 && rc=0 || rc=$?
check "an error from before the push is ignored until timeout" 1 "$rc"
check "the timeout says so" "Timed out" "${EVAL_ERROR:0:9}"

# Hydra has checked twice since the push without producing a new evaluation:
# the jobs are unchanged, so the latest listed evaluation is the result.
# hydra_get runs in a command substitution, so count calls through a file.
count_file=$(mktemp)
echo 0 >"$count_file"
hydra_get() {
  case $1 in
    */evals) echo "$EVALS" ;;
    *)
      n=$(($(cat "$count_file") + 1))
      echo "$n" >"$count_file"
      echo "{\"lastcheckedtime\":$((200 + n)),\"errormsg\":\"\",\"fetcherrormsg\":null}"
      ;;
  esac
}
wait_for_eval "$REV" 100 && rc=0 || rc=$?
check "unchanged jobs fall back to the latest evaluation" "0 6" "$rc $(jq -r .id <<<"$EVAL_JSON")"
rm -f "$count_file"

# --- success_report --------------------------------------------------------
FUB_HYDRA_PUBLIC_URL=https://hydra.example
SUMMARY=$(gating_summary juicy-j <<<"[$ok_j]")
check "success_report renders a table row" \
  '| `juicy-j` | [70](https://hydra.example/build/70) | `/nix/store/a` |' \
  "$(success_report | tail -n 1)"

if ((fails > 0)); then
  echo "$fails test(s) failed"
  exit 1
fi
echo "all tests passed"
````

- [ ] **Step 2 (AGENT): Run the tests and see them fail**

```bash
bash packages/flake-update-bot/tests.sh
```

Expected: FAIL with `./flake-update-bot.sh: No such file or directory`.

- [ ] **Step 3 (AGENT): Write the orchestrator, `packages/flake-update-bot/flake-update-bot.sh`**

It has no shebang and no `set -e`: `writeShellApplication` adds both.

````bash
# flake-update-bot: update flake.lock, open a PR, gate it on Hydra, and let
# Claude Code try to fix a failing build. Configured through the environment
# by modules/nixos/flake-update-bot; secrets come from systemd credentials.

: "${FUB_REPO:?owner/name of the GitHub repo}"
: "${FUB_HOSTS:?space-separated hosts whose nixos.<host> job gates the PR}"
FUB_BRANCH=${FUB_BRANCH:-flake-update}
FUB_BASE=${FUB_BASE:-master}
FUB_HYDRA_URL=${FUB_HYDRA_URL:-http://127.0.0.1:3001}
FUB_HYDRA_PUBLIC_URL=${FUB_HYDRA_PUBLIC_URL:-$FUB_HYDRA_URL}
FUB_HYDRA_PROJECT=${FUB_HYDRA_PROJECT:-all-the-nix}
FUB_HYDRA_JOBSET=${FUB_HYDRA_JOBSET:-flake-update}
FUB_MAX_FIX_ATTEMPTS=${FUB_MAX_FIX_ATTEMPTS:-3}
FUB_STATE_DIR=${FUB_STATE_DIR:-$HOME/.local/state/flake-update-bot}
FUB_EVAL_TIMEOUT=${FUB_EVAL_TIMEOUT:-2700}
FUB_BUILD_TIMEOUT=${FUB_BUILD_TIMEOUT:-21600}
FUB_CLAUDE_TIMEOUT=${FUB_CLAUDE_TIMEOUT:-3600}
FUB_POLL=${FUB_POLL:-30}
# Testing aid: skip the lock update and gate whatever is already on FUB_BRANCH.
FUB_SKIP_UPDATE=${FUB_SKIP_UPDATE:-}

EVAL_JSON=""
EVAL_ERROR=""
SUMMARY=""

log() { printf '%s %s\n' "$(date -Is)" "$*" >&2; }

cred() { cat "${CREDENTIALS_DIRECTORY:?not started by systemd}/$1"; }

hydra_get() {
  curl -fsS --retry 5 --retry-all-errors --retry-delay 5 \
    -H 'Accept: application/json' "$FUB_HYDRA_URL$1"
}

jobset_path() { printf '/jobset/%s/%s' "$FUB_HYDRA_PROJECT" "$FUB_HYDRA_JOBSET"; }

# Print the evaluation whose locked flake ref contains revision $1, if any.
# Hydra only lists evaluations that produced new builds.
find_eval() {
  hydra_get "$(jobset_path)/evals" |
    jq -c --arg rev "$1" 'first(.evals[] | select((.flake // "") | contains($rev))) // empty'
}

# stdin: JSON array of Hydra build objects. args: gating hosts.
# stdout: {state, missing, pending, failed, ok}; state is pending|failure|success.
gating_summary() {
  local hosts_json
  hosts_json=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
  jq -c --argjson hosts "$hosts_json" '
    def done: .finished == 1 or .finished == true;
    . as $builds
    | [ $hosts[] | "nixos." + . | . as $job
        | { job: $job, build: ($builds | map(select(.job == $job)) | first) } ] as $rows
    | {
        missing: [ $rows[] | select(.build == null) | .job ],
        pending: [ $rows[] | select(.build != null and (.build | done | not))
                   | { job, id: .build.id } ],
        failed:  [ $rows[] | select(.build != null and (.build | done) and .build.buildstatus != 0)
                   | { job, id: .build.id, buildstatus: .build.buildstatus, drvpath: .build.drvpath } ],
        ok:      [ $rows[] | select(.build != null and (.build | done) and .build.buildstatus == 0)
                   | { job, id: .build.id, out: (.build.buildoutputs.out.path // null) } ]
      }
    | .state = (if (.pending | length) > 0 then "pending"
                elif ((.missing | length) + (.failed | length)) > 0 then "failure"
                else "success" end)'
}

# Wait for Hydra to evaluate revision $1, pushed at epoch $2.
# Success: EVAL_JSON is set. Failure: EVAL_ERROR is set and 1 is returned.
wait_for_eval() {
  local rev=$1 since=$2 deadline=$((SECONDS + FUB_EVAL_TIMEOUT))
  local first_check="" js lct errtime msg
  EVAL_JSON="" EVAL_ERROR=""
  while ((SECONDS < deadline)); do
    EVAL_JSON=$(find_eval "$rev")
    [[ -n $EVAL_JSON ]] && return 0
    js=$(hydra_get "$(jobset_path)")
    lct=$(jq -r '.lastcheckedtime // 0' <<<"$js")
    if ((lct >= since)); then
      errtime=$(jq -r '.errortime // 0' <<<"$js")
      msg=$(jq -r '.errormsg // ""' <<<"$js")
      if [[ -n $msg ]] && ((errtime >= since)); then
        EVAL_ERROR=$msg
        return 1
      fi
      # A fetch error is usually transient: remember it and keep polling.
      EVAL_ERROR=$(jq -r '.fetcherrormsg // ""' <<<"$js")
      if [[ -z $EVAL_ERROR ]]; then
        if [[ -z $first_check ]]; then
          first_check=$lct
        elif ((lct > first_check)); then
          # Checked twice since the push and still no evaluation for this
          # revision: the jobs are identical to the latest listed evaluation.
          EVAL_JSON=$(hydra_get "$(jobset_path)/evals" | jq -c '.evals[0] // empty')
          [[ -n $EVAL_JSON ]] && return 0
          EVAL_ERROR="Hydra checked the jobset but has no evaluation at all."
          return 1
        fi
      fi
    fi
    sleep "$FUB_POLL"
  done
  EVAL_ERROR=${EVAL_ERROR:-"Timed out after ${FUB_EVAL_TIMEOUT}s waiting for Hydra to evaluate $rev."}
  return 1
}

# Wait for the gating builds of EVAL_JSON to finish. Sets SUMMARY.
wait_for_builds() {
  local deadline=$((SECONDS + FUB_BUILD_TIMEOUT)) id builds
  local -a hosts
  read -r -a hosts <<<"$FUB_HOSTS"
  while :; do
    builds=$(for id in $(jq -r '.builds[]' <<<"$EVAL_JSON"); do hydra_get "/build/$id"; done | jq -sc .)
    SUMMARY=$(gating_summary "${hosts[@]}" <<<"$builds")
    [[ $(jq -r .state <<<"$SUMMARY") != pending ]] && return 0
    if ((SECONDS >= deadline)); then
      SUMMARY=$(jq -c '.state = "failure" | .timedout = true' <<<"$SUMMARY")
      return 0
    fi
    sleep "$FUB_POLL"
  done
}

# Re-run a failed derivation locally to get Nix's own error and log tail.
# Everything that did build is already in the store, so only the failure reruns.
build_log_tail() {
  timeout 2h nix build --no-link --keep-going --log-lines 60 "$1^*" 2>&1 | tail -n 80 || true
}

success_report() {
  jq -r --arg url "$FUB_HYDRA_PUBLIC_URL" '
    "| Host | Hydra build | Output |", "|---|---|---|",
    (.ok[] | "| `\(.job | ltrimstr("nixos."))` | [\(.id)](\($url)/build/\(.id)) | `\(.out)` |")' <<<"$SUMMARY"
}

failure_report() {
  local job id status drv missing
  if [[ $(jq -r '.timedout // false' <<<"$SUMMARY") == true ]]; then
    printf 'Timed out after %ss waiting for these builds: %s\n\n' "$FUB_BUILD_TIMEOUT" \
      "$(jq -r '[.pending[].job] | join(", ")' <<<"$SUMMARY")"
  fi
  while IFS=$'\t' read -r job id status drv; do
    printf '#### `%s`: [build %s](%s/build/%s) failed (status %s)\n\n```\n' \
      "$job" "$id" "$FUB_HYDRA_PUBLIC_URL" "$id" "$status"
    build_log_tail "$drv"
    printf '```\n\n'
  done < <(jq -r '.failed[] | [.job, .id, .buildstatus, .drvpath] | @tsv' <<<"$SUMMARY")
  missing=$(jq -r '[.missing[]] | join(", ")' <<<"$SUMMARY")
  if [[ -n $missing ]]; then
    printf '#### Not evaluated: %s\n\n```\n' "$missing"
    hydra_get "$(jobset_path)" | jq -r '.errormsg // ""' | tail -n 60
    printf '```\n\n'
  fi
}

# Gate revision $1 (pushed at epoch $2) on Hydra. Writes markdown to $3.
gate() {
  local rev=$1 since=$2 out=$3
  log "waiting for Hydra to evaluate $rev"
  if ! wait_for_eval "$rev" "$since"; then
    printf 'Hydra did not produce an evaluation for `%s`.\n\n```\n%s\n```\n' \
      "$rev" "$(tail -n 60 <<<"$EVAL_ERROR")" >"$out"
    return 1
  fi
  log "evaluation $(jq -r .id <<<"$EVAL_JSON"); waiting for builds"
  wait_for_builds
  if [[ $(jq -r .state <<<"$SUMMARY") == success ]]; then
    success_report >"$out"
    return 0
  fi
  failure_report >"$out"
  return 1
}

gh_() { GH_TOKEN=$(cred gh-token) gh "$@"; }

comment() { gh_ pr comment "$1" -R "$FUB_REPO" --body-file "$2" >/dev/null; }

push_branch() {
  local token_file="$CREDENTIALS_DIRECTORY/gh-token"
  git -c credential.helper= \
    -c "credential.helper=!f() { echo username=x-access-token; echo \"password=\$(cat '$token_file')\"; }; f" \
    push --force origin "HEAD:refs/heads/$FUB_BRANCH"
}

notify() {
  local dir=${CREDENTIALS_DIRECTORY:-}
  [[ -r $dir/pushover-user && -r $dir/pushover-token ]] || return 0
  curl -fsS -o /dev/null \
    --form-string "token=$(cred pushover-token)" \
    --form-string "user=$(cred pushover-user)" \
    --form-string "title=flake update" \
    --form-string "message=$1" \
    https://api.pushover.net/1/messages.json || log "pushover notification failed"
}

# Let Claude Code attempt a fix. $1: failure report, $2: file for its summary.
# Returns 0 only if it committed something.
run_claude() {
  local report=$1 summary=$2 before prompt
  before=$(git rev-parse HEAD)
  prompt=$(
    cat <<EOF
You are running unattended in a clone of the $FUB_REPO flake, on branch
$FUB_BRANCH. The last commits updated flake.lock, and Hydra failed to build the
NixOS system closures for: $FUB_HOSTS. The failure report follows.

$(cat "$report")

Fix it so that this builds for every host listed above:

  nix build --no-link .#nixosConfigurations.<host>.config.system.build.toplevel

Rules:
- Make the smallest change that fixes the build. Do not refactor.
- Do not remove features, hosts or packages to get a green build, unless the
  package was removed upstream; say so if that is the case.
- Pinning a single input back to its previous revision is acceptable if a real
  fix is not practical. Explain why.
- Run the nix build above for each failing host and confirm it succeeds.
- New files must be git-added before nix can see them.
- Commit your fix on the current branch. Do not push.
- Your final message is posted on the pull request: say what was wrong, what
  you changed, and how you verified it, in under 200 words.
EOF
  )
  log "running claude"
  CLAUDE_CODE_OAUTH_TOKEN=$(cred claude-token) \
    CLAUDE_CONFIG_DIR="$FUB_STATE_DIR/claude" \
    BASH_DEFAULT_TIMEOUT_MS=3600000 BASH_MAX_TIMEOUT_MS=3600000 \
    timeout "$FUB_CLAUDE_TIMEOUT" claude -p "$prompt" \
    --permission-mode dontAsk \
    --allowedTools Read Edit Write Glob Grep \
    'Bash(nix:*)' 'Bash(git add:*)' 'Bash(git commit:*)' 'Bash(git diff:*)' \
    'Bash(git status:*)' 'Bash(git log:*)' 'Bash(git show:*)' \
    >"$summary" 2>"$FUB_STATE_DIR/claude-stderr.log" || log "claude exited non-zero"
  git reset --hard -q
  git clean -fdq
  [[ $(git rev-parse HEAD) != "$before" ]]
}

prepare_repo() {
  local repo="$FUB_STATE_DIR/repo"
  if [[ ! -d $repo/.git ]]; then
    git clone "https://github.com/$FUB_REPO.git" "$repo"
  fi
  cd "$repo"
  git fetch --prune origin
  git reset --hard -q
  git clean -fdq
}

open_pr_number() {
  gh_ pr list -R "$FUB_REPO" --head "$FUB_BRANCH" --state open --json number --jq '.[0].number // empty'
}

main() {
  local tmp update_log pr rev since report summary attempt=0 old
  mkdir -p "$FUB_STATE_DIR"
  exec 9>"$FUB_STATE_DIR/lock"
  flock -n 9 || {
    log "another run holds the lock"
    exit 0
  }
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  report=$tmp/report.md
  summary=$tmp/claude-summary.md
  update_log=$tmp/update.log

  prepare_repo
  since=$(date +%s)
  if [[ -n $FUB_SKIP_UPDATE ]]; then
    git checkout -q -B "$FUB_BRANCH" "origin/$FUB_BRANCH"
    pr=$(open_pr_number)
  else
    git checkout -q -B "$FUB_BRANCH" "origin/$FUB_BASE"
    nix flake update 2>"$update_log" || {
      cat "$update_log" >&2
      exit 1
    }
    if git diff --quiet -- flake.lock; then
      log "flake.lock is already up to date"
      exit 0
    fi
    {
      printf 'flake update %s\n\n' "$(date +%F)"
      grep -v '^warning:' "$update_log" || true
    } >"$tmp/commit-msg"
    git commit -q -F "$tmp/commit-msg" -- flake.lock
    old=$(open_pr_number)
    if [[ -n $old ]]; then
      gh_ pr close "$old" -R "$FUB_REPO" --comment "Superseded by this week's update."
    fi
    push_branch
    pr=""
  fi
  if [[ -z $pr ]]; then
    {
      printf 'Weekly `nix flake update`. Hydra builds: %s.\n\n```\n' "$FUB_HOSTS"
      git log -1 --format=%b
      printf '```\n'
    } >"$tmp/pr-body"
    gh_ pr create -R "$FUB_REPO" --base "$FUB_BASE" --head "$FUB_BRANCH" \
      --title "$(git log -1 --format=%s)" --body-file "$tmp/pr-body" >/dev/null
    pr=$(open_pr_number)
  fi
  rev=$(git rev-parse HEAD)
  log "PR #$pr at $rev"

  if gate "$rev" "$since" "$report"; then
    { printf '### ✅ Hydra build succeeded\n\n'; cat "$report"; } >"$tmp/comment"
    comment "$pr" "$tmp/comment"
    notify "PR #$pr: build succeeded"
    exit 0
  fi
  { printf '### ❌ Hydra build failed\n\n'; cat "$report"; } >"$tmp/comment"
  comment "$pr" "$tmp/comment"

  while ((attempt < FUB_MAX_FIX_ATTEMPTS)); do
    attempt=$((attempt + 1))
    if ! run_claude "$report" "$summary"; then
      printf '### ❌ Fix attempt %s: Claude did not produce a commit\n\n%s\n' \
        "$attempt" "$(cat "$summary")" >"$tmp/comment"
      comment "$pr" "$tmp/comment"
      continue
    fi
    since=$(date +%s)
    push_branch
    rev=$(git rev-parse HEAD)
    if gate "$rev" "$since" "$report"; then
      {
        printf '### ✅ Fixed by Claude on attempt %s\n\n%s\n\n' "$attempt" "$(cat "$summary")"
        cat "$report"
      } >"$tmp/comment"
      comment "$pr" "$tmp/comment"
      notify "PR #$pr: build fixed by Claude on attempt $attempt"
      exit 0
    fi
    {
      printf '### ❌ Fix attempt %s did not build\n\n%s\n\n' "$attempt" "$(cat "$summary")"
      cat "$report"
    } >"$tmp/comment"
    comment "$pr" "$tmp/comment"
  done

  printf '### 🛑 Giving up after %s fix attempt(s)\n\nThe branch is left as it is for a human.\n' \
    "$attempt" >"$tmp/comment"
  comment "$pr" "$tmp/comment"
  notify "PR #$pr: build failed, gave up after $attempt fix attempt(s)"
  exit 1
}

if [[ -z ${FUB_LIB_ONLY:-} ]]; then
  main "$@"
fi
````

- [ ] **Step 4 (AGENT): Run the tests and see them pass**

```bash
bash packages/flake-update-bot/tests.sh
```

Expected: 16 `ok` lines, then `all tests passed`.

- [ ] **Step 5 (AGENT): Create `packages/flake-update-bot/default.nix`**

```nix
{
  pkgs,
  writeShellApplication,
  git,
  gh,
  curl,
  jq,
  util-linux,
  coreutils,
  gnugrep,
  ...
}:
writeShellApplication {
  name = "flake-update-bot";
  # nix is deliberately absent: the service puts the system's Determinate Nix
  # on PATH, and the bot must evaluate with the same Nix the hosts use.
  runtimeInputs = [
    git
    gh
    curl
    jq
    util-linux
    coreutils
    gnugrep
    pkgs.unstable.claude-code
  ];
  # SC2016: the script prints markdown, so backticks inside single-quoted
  # printf formats are literal, not forgotten expansions.
  excludeShellChecks = [ "SC2016" ];
  text = builtins.readFile ./flake-update-bot.sh;
  meta.description = "weekly flake.lock update PR, gated on Hydra, with a Claude Code fix loop";
}
```

- [ ] **Step 6 (AGENT): Build it (this runs shellcheck over the orchestrator)**

```bash
git add packages/flake-update-bot
nix fmt && statix check
nix build --no-link --print-out-paths .#flake-update-bot
```

Expected: a store path, no shellcheck findings.

- [ ] **Step 7 (AGENT): Commit**

```bash
git add packages/flake-update-bot
git commit -m "flake-update-bot: orchestrator package

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The NixOS module, secrets, and enabling it on juicy-j

**Files:**
- Create: `modules/nixos/flake-update-bot/default.nix`
- Create: `modules/nixos/flake-update-bot/CLAUDE.md`
- Modify: `secrets.nix`
- Create (USER): `secrets/flake-update-bot-gh-token.age`, `secrets/claude-oauth-token.age`
- Modify: `systems/x86_64-linux/juicy-j/default.nix`

- [ ] **Step 1 (AGENT): Declare the secrets' recipients**

In `secrets.nix`, add inside the attribute set, after the `openclaw-gateway-token` line:

```nix
  "secrets/flake-update-bot-gh-token.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/claude-oauth-token.age".publicKeys = burke ++ [ juicy-j ];
```

- [ ] **Step 2 (USER): Create the two secrets**

1. On GitHub, create a fine-grained personal access token limited to the `burk3/all-the-nix` repository with **Contents: Read and write** and **Pull requests: Read and write**.
2. Run `claude setup-token` and copy the token it prints.
3. In the repo, inside `nix develop`:

```bash
agenix -e secrets/flake-update-bot-gh-token.age   # paste the GitHub token, no trailing newline needed
agenix -e secrets/claude-oauth-token.age          # paste the Claude token
git add secrets/flake-update-bot-gh-token.age secrets/claude-oauth-token.age
```

- [ ] **Step 3 (AGENT): Create `modules/nixos/flake-update-bot/default.nix`**

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.flakeUpdateBot;
  secret = name: config.age.secrets.${name}.path;
in
with lib;
{
  options.t11s.flakeUpdateBot = {
    enable = mkEnableOption "weekly flake.lock update PRs, gated on Hydra, with a Claude Code fix loop";
    repo = mkOption {
      type = types.str;
      example = "burk3/all-the-nix";
      description = "GitHub owner/name of the flake to update";
    };
    hosts = mkOption {
      type = types.listOf types.str;
      description = "hosts whose hydraJobs.nixos.<host> build gates the PR";
    };
    schedule = mkOption {
      type = types.str;
      default = "Sat 04:00";
      description = "systemd OnCalendar expression for the run";
    };
    maxFixAttempts = mkOption {
      type = types.ints.unsigned;
      default = 3;
      description = "how many times Claude Code may try to fix a failing build";
    };
  };

  config = mkIf cfg.enable {
    age.secrets."flake-update-bot-gh-token".file = ../../../secrets/flake-update-bot-gh-token.age;
    age.secrets."claude-oauth-token".file = ../../../secrets/claude-oauth-token.age;
    age.secrets."pushover-user-key".file = ../../../secrets/pushover-user-key.age;
    age.secrets."pushover-api-token".file = ../../../secrets/pushover-api-token.age;

    systemd.services.flake-update-bot = {
      description = "Weekly flake.lock update PR, gated on Hydra";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "hydra-server.service"
      ];
      startAt = cfg.schedule;
      # The system profile supplies Determinate Nix and the shell tools Claude
      # Code's Bash tool expects.
      path = [ "/run/current-system/sw" ];
      environment = {
        FUB_REPO = cfg.repo;
        FUB_HOSTS = concatStringsSep " " cfg.hosts;
        FUB_MAX_FIX_ATTEMPTS = toString cfg.maxFixAttempts;
        FUB_HYDRA_URL = "http://127.0.0.1:${toString config.services.hydra.port}";
        FUB_HYDRA_PUBLIC_URL = config.services.hydra.hydraURL;
      };
      serviceConfig = {
        Type = "oneshot";
        # Runs as the main user on purpose: it works in a clone under their
        # home and commits as them. systemd reads the secrets as root and
        # hands them over through the credentials directory.
        User = config.t11s.mainUser.name;
        ExecStart = getExe pkgs.t11s.flake-update-bot;
        TimeoutStartSec = "24h";
        LoadCredential = [
          "gh-token:${secret "flake-update-bot-gh-token"}"
          "claude-token:${secret "claude-oauth-token"}"
          "pushover-user:${secret "pushover-user-key"}"
          "pushover-token:${secret "pushover-api-token"}"
        ];
      };
    };
    systemd.timers.flake-update-bot.timerConfig.Persistent = true;
  };
}
```

- [ ] **Step 4 (AGENT): Create `modules/nixos/flake-update-bot/CLAUDE.md`**

```markdown
# flake-update-bot

`t11s.flakeUpdateBot` runs `pkgs.t11s.flake-update-bot` weekly on the host that also runs Hydra (juicy-j). The orchestrator is `packages/flake-update-bot/flake-update-bot.sh`; its Hydra logic is covered by `bash packages/flake-update-bot/tests.sh`.

- It works in its own clone at `~/.local/state/flake-update-bot/repo`, on branch `flake-update`, and never merges.
- Hydra is the gate: the bot pushes, then polls Hydra's JSON API for the evaluation of that commit. Hydra polls the branch itself (jobsets are declared in `systems/x86_64-linux/juicy-j/hydra.nix`).
- On failure it runs headless `claude` with a tool allowlist and its own `CLAUDE_CONFIG_DIR`. Claude never gets the GitHub token; the orchestrator pushes.
- It runs as the main user, so the allowlist is a guardrail, not a sandbox.
- Manual run: `sudo systemctl start flake-update-bot`, then `journalctl -fu flake-update-bot`.
- To test against an existing `flake-update` branch without updating the lock, set `FUB_SKIP_UPDATE=1` through a runtime drop-in.
```

- [ ] **Step 5 (AGENT): Enable it on juicy-j**

In `systems/x86_64-linux/juicy-j/default.nix`, after the `t11s.internalCA.enable = true;` line, add:

```nix
  t11s.flakeUpdateBot = {
    enable = true;
    repo = "burk3/all-the-nix";
    hosts = [
      "juicy-j"
      "freddie-kane"
    ];
  };
```

- [ ] **Step 6 (AGENT): Check it evaluates**

```bash
git add modules/nixos/flake-update-bot secrets.nix
nix fmt && statix check
nix eval --json .#nixosConfigurations.juicy-j.config.systemd.services.flake-update-bot.environment
nix eval --json .#nixosConfigurations.juicy-j.config.systemd.timers.flake-update-bot.timerConfig
nix eval --json .#nixosConfigurations.juicy-j.config.systemd.services.flake-update-bot.serviceConfig.LoadCredential
nix eval --json .#nixosConfigurations.freddie-kane.config.t11s.flakeUpdateBot.enable
```

Expected: `FUB_HOSTS` is `juicy-j freddie-kane` and `FUB_HYDRA_URL` is `http://127.0.0.1:3001`; `OnCalendar` is `["Sat 04:00"]` and `Persistent` is `true`; four credentials; `false`.

If evaluation fails with conflicting definitions of `age.secrets."pushover-user-key".file`, delete the two `pushover-*` `age.secrets` lines from the module (they are already declared in `systems/x86_64-linux/juicy-j/monitoring.nix`) and re-run.

- [ ] **Step 7 (AGENT): Commit**

```bash
git add modules/nixos/flake-update-bot secrets.nix secrets/flake-update-bot-gh-token.age \
  secrets/claude-oauth-token.age systems/x86_64-linux/juicy-j/default.nix
git commit -m "flake-update-bot: nixos module, enabled on juicy-j

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8 (USER): Switch juicy-j**

```bash
nh os switch .
systemctl list-timers flake-update-bot --no-pager
```

Expected: the timer is listed with its next run on Saturday at 04:00.

---

### Task 8: First real run (success path)

- [ ] **Step 1 (USER): Start a run and follow it**

```bash
sudo systemctl start --no-block flake-update-bot
journalctl -fu flake-update-bot
```

Expected log lines, in order: a clone on the first run, `PR #<n> at <sha>`, `waiting for Hydra to evaluate <sha>`, `evaluation <id>; waiting for builds`, then the unit finishes successfully.

If the log says `flake.lock is already up to date`, nothing was opened: every input is current. That is correct behaviour. Skip to Task 9, which exercises the same PR, Hydra and comment code.

- [ ] **Step 2 (USER): Check the results**

- The PR on GitHub has a "✅ Hydra build succeeded" comment with a row per gating host linking to `https://hydra.ts.t11s.net/build/<id>`.
- A Pushover notification arrived.
- `git -C ~/.local/state/flake-update-bot/repo log -1` shows the commit authored as you.

Common first-run problems and what they mean:

| Symptom in the journal | Cause |
|---|---|
| `gh: Resource not accessible by personal access token` on comment | add **Issues: Read and write** to the token |
| `Author identity unknown` | git has no `user.name`/`user.email` for burke outside an interactive shell; set them in `~/.config/git/config` |
| `Hydra did not produce an evaluation` with a timeout | check `journalctl -u hydra-evaluator`; the `flake-update` jobset polls every 60 s |

- [ ] **Step 3 (USER): Decide what to do with the PR**

Merge it or close it. The bot never merges.

---

### Task 9: Failure path, fix loop and give-up path

This pushes a deliberately broken commit to `flake-update` and opens a throwaway PR.

- [ ] **Step 1 (USER): Push a broken branch**

```bash
cd ~/src/all-the-nix
git fetch origin
git worktree add ../atn-broken -B fub-broken origin/master
cd ../atn-broken
```

In `systems/x86_64-linux/juicy-j/default.nix`, add this line directly after `environment.systemPackages = with pkgs; [ via ];`:

```nix
  environment.etc."fub-broken".source = pkgs.runCommand "fub-broken" { } "echo deliberately broken for the flake-update-bot test; exit 1";
```

```bash
git commit -am "test: deliberately broken build"
git push --force origin HEAD:flake-update
```

- [ ] **Step 2 (USER): Run the bot against that branch without updating the lock**

```bash
sudo mkdir -p /run/systemd/system/flake-update-bot.service.d
printf '[Service]\nEnvironment=FUB_SKIP_UPDATE=1\n' |
  sudo tee /run/systemd/system/flake-update-bot.service.d/test.conf
sudo systemctl daemon-reload
sudo systemctl start --no-block flake-update-bot
journalctl -fu flake-update-bot
```

- [ ] **Step 3 (USER): Check the fix loop**

Expected on the PR, in order:

1. "❌ Hydra build failed" with a log tail containing `deliberately broken for the flake-update-bot test`.
2. A new commit on `flake-update` removing or fixing the broken line, authored locally by Claude Code.
3. "✅ Fixed by Claude on attempt 1" with Claude's summary and the build table.

And a Pushover notification saying the build was fixed. If Claude was denied a tool it needed, `~/.local/state/flake-update-bot/claude-stderr.log` and the "did not produce a commit" comment say which; adjust the `--allowedTools` list in `flake-update-bot.sh` and rerun `tests.sh` and the package build.

- [ ] **Step 4 (USER): Check the give-up path**

```bash
cd ../atn-broken
git push --force origin HEAD:flake-update
printf '[Service]\nEnvironment=FUB_SKIP_UPDATE=1\nEnvironment=FUB_MAX_FIX_ATTEMPTS=0\n' |
  sudo tee /run/systemd/system/flake-update-bot.service.d/test.conf
sudo systemctl daemon-reload
sudo systemctl start --no-block flake-update-bot
journalctl -fu flake-update-bot
```

Expected: "❌ Hydra build failed", then "🛑 Giving up after 0 fix attempt(s)", a Pushover notification, and the unit ends in the failed state (`systemctl is-failed flake-update-bot` prints `failed`).

- [ ] **Step 5 (USER): Clean up**

```bash
sudo rm -r /run/systemd/system/flake-update-bot.service.d
sudo systemctl daemon-reload
sudo systemctl reset-failed flake-update-bot
cd ~/src/all-the-nix
git worktree remove --force ../atn-broken
git branch -D fub-broken
```

Close the test PR on GitHub. Leave the `flake-update` branch in place; the next real run resets it.

---

### Task 10: Documentation and merge

**Files:**
- Modify: `systems/x86_64-linux/juicy-j/CLAUDE.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1 (AGENT): Document Hydra and the bot for juicy-j**

Append to `systems/x86_64-linux/juicy-j/CLAUDE.md`:

```markdown

**Runs Hydra** (`hydra.nix`) at `https://hydra.ts.t11s.net`, building `hydraJobs.nixos.<host>` for the `master` and `flake-update` branches of this repo. Three things there are deliberate:

- The localhost builder is in a machines file only Hydra reads (`services.hydra.buildMachinesFiles`). Do not move it into `nix.buildMachines`: that writes `/etc/nix/machines` and makes interactive `nix build` SSH into this machine.
- Hydra evaluates with Determinate's `nix-eval-jobs` (flake input `nix-eval-jobs`, which deliberately does not follow `determinate/nix`: the fork lags Determinate releases and will not evaluate against a newer nix-src). This keeps Hydra's derivations identical to what `nh os switch` computes on other hosts, which is what lets them substitute from here. If Hydra's `drvPath` for a host ever differs from `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`, clients go back to building.
- The project and jobsets are declared in `hydra.nix` and applied by `hydra-provision` on every switch. Changes made in the web UI are overwritten.

**Runs the weekly flake update** (`t11s.flakeUpdateBot`, Saturday 04:00). See `modules/nixos/flake-update-bot/CLAUDE.md`. Store GC runs Sunday 02:30 to 05:00; keep the two apart.
```

- [ ] **Step 2 (AGENT): Document the cached switch**

In the root `CLAUDE.md`, in the "Common commands" code block, after the `nh os switch .` line, add:

```sh
nh os switch "$(t11s-cached-system)"        # switch to the closure Hydra built for HEAD; no evaluation
```

- [ ] **Step 3 (AGENT): Commit**

```bash
git add CLAUDE.md systems/x86_64-linux/juicy-j/CLAUDE.md
git commit -m "docs: hydra, flake-update-bot and cached switch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4 (AGENT): Final checks**

```bash
nix fmt && statix check
bash packages/flake-update-bot/tests.sh
nix flake check
```

Expected: no formatting changes, no lint findings, `all tests passed`, and `nix flake check` evaluates every output without error.

- [ ] **Step 5: Integrate**

Use superpowers:finishing-a-development-branch to decide with Burke how `hydra-flake-update-bot` reaches `master` (PR or direct merge). Pushing is his call.

- [ ] **Step 6 (USER): The real acceptance test**

After the branch is on `master`, Hydra has built it, and the next weekly PR has been merged, on freddie-kane:

```bash
cd ~/src/all-the-nix; git co master; git pull
nh os switch . --dry
```

Expected: paths to fetch from juicy-j, nothing to build.
