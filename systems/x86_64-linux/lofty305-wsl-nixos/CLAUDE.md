# lofty305-wsl-nixos

WSL host. The `nixos-wsl` module is **not** added via the standard `systems.modules.nixos` pipeline — it's added per-host in `flake.nix:systems.hosts.lofty305-wsl-nixos.modules`. New WSL-only modules should follow the same pattern so non-WSL hosts don't pick them up.
