# remotebuilder

Two complementary modes via the same module:

- `serveBuilds = true` — this host **accepts** inbound builds. Exposes a `remotebuild` user/key for clients to connect with.
- `hosts = [ ... ]` — this host **delegates** builds to the listed builders.

Per-builder parameters (system, max-jobs, supportedFeatures, etc.) are hardcoded in the module's `hostConfigs` table. To add a new builder, add it there first; clients then refer to it by name in `hosts = [ ... ]`.

Clients also **substitute** from each builder over `ssh-ng`, as the same `remotebuild` user with the same root key. The stores are unsigned, so the substituter URL carries `trusted=true`. A `Host` block in the client's system `ssh_config` sets a 5 second connect timeout so an unreachable builder does not hang builds. On juicy-j, Hydra keeps the closures of `master` built, which is what makes `nh os switch` on a client fetch instead of build.
