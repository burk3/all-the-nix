# juicy-j

Framework Desktop (AMD AI Max 300). Workstation. Runs RKE2 (see `rke2.nix`), lanzaboote secure boot, internal CA.

**Serves remote builds** to other hosts in this repo via `t11s.remotebuilder.serveBuilds = true`. Builder-side changes here affect how the other hosts (notably freddie-kane) get their closures.

A custom udev rule in `default.nix` renames the Aquantia SFP+ NIC to `sfp0`. It matches on `DRIVERS=="atlantic"` (not MAC or PCI address): the NIC is USB4/Thunderbolt-attached, so its PCIe bus address is enumerated at hotplug and isn't stable, and matching by driver avoids committing the MAC to this public repo. This works because `atlantic` is the only such NIC on the box — if a second Aquantia adapter is ever added, disambiguate with `ATTRS{subsystem_vendor}`/`ATTRS{subsystem_device}` rather than reverting to MAC.

**Runs Hydra** (`hydra.nix`) at `https://hydra.ts.t11s.net`, building `hydraJobs.nixos.<host>` for the `master` and `flake-update` branches of this repo. Three things there are deliberate:

- The localhost builder is in a machines file only Hydra reads (`services.hydra.buildMachinesFiles`). Do not move it into `nix.buildMachines`: that writes `/etc/nix/machines` and makes interactive `nix build` SSH into this machine.
- Hydra evaluates with Determinate's `nix-eval-jobs` (flake input `nix-eval-jobs`, which deliberately does not follow `determinate/nix`: the fork lags Determinate releases and will not evaluate against a newer nix-src). This keeps Hydra's derivations identical to what `nh os switch` computes on other hosts, which is what lets them substitute from here. If Hydra's `drvPath` for a host ever differs from `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`, clients go back to building.
- The project and jobsets are declared in `hydra.nix` and applied by `hydra-provision` on every switch. Changes made in the web UI are overwritten.

**Runs the weekly flake update** (`t11s.flakeUpdateBot`, Saturday 04:00). See `modules/nixos/flake-update-bot/CLAUDE.md`. Store GC runs Sunday 02:30 to 05:00; keep the two apart.
