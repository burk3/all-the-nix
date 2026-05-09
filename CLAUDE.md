# CLAUDE.md

Personal NixOS + home-manager monorepo built on [snowfall-lib](https://github.com/snowfallorg/lib). Snowfall namespace is **`t11s`** — custom modules expose `options.t11s.<name>` and packages are `pkgs.t11s.<name>`. `unstable` nixpkgs is exposed as an overlay (`pkgs.unstable.<pkg>`).

## Layout (snowfall auto-discovery)

Files are picked up by directory convention — no central import list to maintain.

| Path | Produces |
|------|----------|
| `systems/<arch>/<hostname>/default.nix` | NixOS configuration `<hostname>` |
| `homes/<arch>/<user@hostname>/default.nix` | home-manager config; per-user-host modules go in `flake.nix:homes.users.<user@host>.modules` |
| `modules/nixos/<name>/default.nix` | NixOS module exposing `options.t11s.<name>` |
| `modules/home/<name>/default.nix` | home-manager module exposing `options.t11s.<name>` |
| `packages/<name>/default.nix` | Package available as `pkgs.t11s.<name>` |
| `overlays/<name>/default.nix` | Overlay applied to all systems |
| `shells/nix-dev/default.nix` | Dev shell; aliased as `shells.default` |

Module/host specifics live in per-dir `CLAUDE.md` files (auto-loaded when working in that subtree).

## Module pattern

Every custom module follows the same shape:

```nix
{ config, lib, ... }:
let cfg = config.t11s.<feature>; in
with lib;
{
  options.t11s.<feature> = { enable = mkEnableOption "..."; ... };
  config = mkIf cfg.enable { ... };
}
```

The base module (`modules/nixos/base`) defines `t11s.systemType` (`laptop` | `workstation` | `wsl` | `server`). Cross-cutting behavior branches on this via `isWsl = systemType == "wsl"` and `hasScreen = systemType ∈ {workstation, laptop}`. **Branch on `systemType` rather than introducing new flags.**

When adding a new host, set the standard knobs in its `default.nix`: `t11s.enable`, `t11s.systemType`, `t11s.mainUser.{name,description}`, and (usually) `t11s.caches.enable` and `t11s.internalCA.enable`.

## Common commands

Default dev shell (`nix develop`) provides `cachix`, `lorri`, `niv`, `nil`, `nixfmt-rfc-style`, `nixfmt-tree`, `statix`, `dhall-nix`, `agenix`. `direnv` (`use flake`) is wired up via `.envrc`.

```sh
nix develop                                 # enter dev shell
nix fmt                                     # format (nixfmt-tree)
statix check                                # lint
nix flake check                             # evaluate everything
nix flake lock --update-input <name>        # bump one input

# Build/switch a host (run on that host, or with --target-host)
sudo nixos-rebuild switch --flake .#<hostname>
nh os switch .                              # nh wrapper, installed by personal home module

# Home-manager only
home-manager switch --flake .#<user@host>
nh home switch .

# Build a package defined here
nix build .#t11s-step
```

## Conventions

- **Nix experimental features**: `nix-command flakes parallel-eval pipe-operators` + `lazy-trees = true` + `eval-cores = 0` — set system-wide by `modules/nixos/base`. Code may use pipe-operators syntax (`|>`); don't "fix" it.
- **`lazy-trees = true` gotcha**: new files must be `git add`-ed (not necessarily committed) before `nix build` sees them.
- **`allowUnfree = true`** globally.
- **Catppuccin** is enabled across NixOS and home-manager; flavor/accent exposed via `t11s.personal.{catppuccinFlavor,catppuccinAccent}`.
