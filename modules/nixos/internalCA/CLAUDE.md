# internalCA

Trusts the **tactilecactus** internal CA — root cert at `root_ca.crt`. Wires the step user-CA into sshd and installs a systemd timer that renews the SSH host cert hourly via `pkgs.t11s.t11s-step` (a `step-cli` wrapper preconfigured with the CA bundle in `packages/t11s-step/step/`). Renewal only works on a cert that has not expired. `sudo t11s-sign-host-key` (installed on every sshd host) does the first signing, and re-signs an expired cert, using the `burke@t11s.net` provisioner (it prompts for the password). The cert key ID is `<host>.t11s.net` and its principals are `<host>.lan` and `<host>.dab-ling.ts.net`.

If the upstream CA bundle changes, the bundle in `packages/t11s-step/step/` needs updating alongside `root_ca.crt`.
