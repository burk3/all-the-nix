# internalCA

Trusts the **tactilecactus** internal CA — root cert at `root_ca.crt`. Wires the step user-CA into sshd and installs a systemd timer that renews the SSH host cert hourly via `pkgs.t11s.t11s-step` (a `step-cli` wrapper preconfigured with the CA bundle in `packages/t11s-step/step/`).

If the upstream CA bundle changes, the bundle in `packages/t11s-step/step/` needs updating alongside `root_ca.crt`.
