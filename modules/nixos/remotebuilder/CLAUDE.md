# remotebuilder

Two complementary modes via the same module:

- `serveBuilds = true` — this host **accepts** inbound builds. Exposes a `remotebuild` user/key for clients to connect with.
- `hosts = [ ... ]` — this host **delegates** builds to the listed builders.

Per-builder parameters (system, max-jobs, supportedFeatures, etc.) are hardcoded in the module's `hostConfigs` table. To add a new builder, add it there first; clients then refer to it by name in `hosts = [ ... ]`.
