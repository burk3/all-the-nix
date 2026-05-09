# juicy-j

Framework Desktop (AMD AI Max 300). Workstation. Runs RKE2 (see `rke2.nix`), lanzaboote secure boot, internal CA.

**Serves remote builds** to other hosts in this repo via `t11s.remotebuilder.serveBuilds = true`. Builder-side changes here affect how the other hosts (notably freddie-kane) get their closures.

Custom udev rules in `default.nix` rename the SFP+ NICs to `sfp0`/`sfp1` by MAC. If the NIC hardware is ever replaced, the MACs in those rules need updating.
