# juicy-j

Framework Desktop (AMD AI Max 300). Workstation. Runs lanzaboote secure boot, internal CA.

**Serves remote builds** to other hosts in this repo via `t11s.remotebuilder.serveBuilds = true`. Builder-side changes here affect how the other hosts (notably freddie-kane) get their closures.

A custom udev rule in `default.nix` renames the Aquantia SFP+ NIC to `sfp0`. It matches on `DRIVERS=="atlantic"` (not MAC or PCI address): the NIC is USB4/Thunderbolt-attached, so its PCIe bus address is enumerated at hotplug and isn't stable, and matching by driver avoids committing the MAC to this public repo. This works because `atlantic` is the only such NIC on the box — if a second Aquantia adapter is ever added, disambiguate with `ATTRS{subsystem_vendor}`/`ATTRS{subsystem_device}` rather than reverting to MAC.

**Runs Hydra** (`hydra.nix`) at `https://hydra.ts.t11s.net`, building `hydraJobs.nixos.<host>` for the branches in its `jobsets` (`master`, `flake-update`, `prep-2611`). Three things there are deliberate:

- Builders dial in to the queue runner over gRPC (`services.hydra-builder`, set up by `t11s.hydraBuilder` in `modules/nixos/hydra-builder`): juicy-j's own for x86_64/i686, swaine's for aarch64-linux (`nixos.swaine`). Each one authenticates with its own token, `secrets/hydra-builder-<host>.token.age`. A new builder needs its token added to `agenix-rules.nix` (encrypted to the builder and juicy-j), plus its name in `builders` in `hydra.nix`, which lists the token in `tokenPaths`. gRPC is plain (no TLS) on port 50051, open on the wired LAN interfaces only. The queue runner accepts any client cert that chains to its CA and never checks the name, so mTLS against the shared t11s CA would let any cert that CA issued build. That is why it uses tokens. Hydra's builders have nothing to do with `/etc/nix/machines` here, which holds swaine for interactive builds (`t11s.remotebuild.hosts`). `t11s.nixbuild-dot-net` is still in the flake but disabled.
- Hydra evaluates with Determinate's `nix-eval-jobs` (flake input `nix-eval-jobs`, which deliberately does not follow `determinate/nix`: the fork lags Determinate releases and will not evaluate against a newer nix-src). This keeps Hydra's derivations identical to what `nh os switch` computes on other hosts, which is what lets them substitute from here. If Hydra's `drvPath` for a host ever differs from `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`, clients go back to building.
- The project and jobsets are declared in `hydra.nix` and applied by `hydra-provision` on every switch. Changes made in the web UI are overwritten.

Claude Code sessions on juicy-j have a Hydra account, `claude`, also set up by `hydra-provision`. It can start evaluations, and restart, cancel or bump builds (roles `eval-jobset`, `restart-jobs`, `cancel-build`, `bump-to-front`); it can't edit projects or jobsets. Reading the API needs no login. Its password is `/run/agenix/hydra-claude-password-burke`. Hydra rejects POSTs without a `Referer` from its own URL:

```sh
h=https://hydra.ts.t11s.net; c=$(mktemp)
jq -n --rawfile p /run/agenix/hydra-claude-password-burke '{username: "claude", password: ($p | rtrimstr("\n"))}' |
  curl -fsS --referer $h -H 'Content-Type: application/json' -H 'Accept: application/json' -c $c -d @- $h/login >/dev/null
curl -fsS --referer $h -b $c -X POST -H 'Accept: application/json' "$h/api/push?jobsets=all-the-nix:prep-2611"   # evaluate now
```

**Runs the weekly flake update** (`t11s.flakeUpdateBot`, Saturday 04:00). See `modules/nixos/flake-update-bot/CLAUDE.md`. Store GC runs Sunday 02:30 to 05:00; keep the two apart.
