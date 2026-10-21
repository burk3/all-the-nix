# remotebuilder

Two complementary modes via the same module:

- `serveBuilds = true` — this host **accepts** inbound builds. Exposes a `remotebuild` user/key for clients to connect with.
- `hosts = [ ... ]` — this host **delegates** builds to the listed builders.

Per-builder parameters (addresses, system, max-jobs, supportedFeatures, etc.) are hardcoded in the module's `hostConfigs` table, keyed by short name. To add a new builder, add it there first; clients then refer to it by that name in `hosts = [ ... ]` (an enum, so a typo fails evaluation).

Each builder has two `addresses`, `lan` (`<host>.lan`) and `tailnet` (`<host>.dab-ling.ts.net`). A client reaches every builder by the one for its `t11s.remotebuild.network`, which defaults to `tailnet` on laptops (they roam) and `lan` on everything else. Everything derived from a builder uses that name: the machines entry, the substituter URL and the ssh_config timeout block. juicy-j's Hydra machines file names `swaine.lan` itself.

Builds go over `ssh-ng`. A builder's ssh host key is either pinned in `hostConfigs.<host>.publicHostKey` (base64, used by both the machines entry and the substituter URL) or left `null`. A `null` key means ssh falls back to `/etc/ssh/ssh_known_hosts`, which trusts the t11s CA for `*.dab-ling.ts.net` (internalCA module), so the builder must have a CA-signed host cert (`t11s-sign-host-key`). swaine works this way.

The `remotebuild` user authorizes `clientKeys`: root's `/root/.ssh/remotebuild` on each client, plus juicy-j's Hydra queue runner, which builds aarch64 jobs on swaine.

Clients also **substitute** from each builder over `ssh-ng`, as the same `remotebuild` user with the same root key. The stores are unsigned, so the substituter URL carries `trusted=true`. A `Host` block in the client's system `ssh_config` sets a 5 second connect timeout so an unreachable builder does not hang builds. On juicy-j, Hydra keeps the closures of `master` built, which is what makes `nh os switch` on a client fetch instead of build.
