# juicy-j

Framework Desktop (AMD AI Max 300). Workstation. Runs RKE2 (see `rke2.nix`), lanzaboote secure boot, internal CA.

**Serves remote builds** to other hosts in this repo via `t11s.remotebuilder.serveBuilds = true`. Builder-side changes here affect how the other hosts (notably freddie-kane) get their closures.

A custom udev rule in `default.nix` renames the Aquantia SFP+ NIC to `sfp0`. It matches on `DRIVERS=="atlantic"` (not MAC or PCI address): the NIC is USB4/Thunderbolt-attached, so its PCIe bus address is enumerated at hotplug and isn't stable, and matching by driver avoids committing the MAC to this public repo. This works because `atlantic` is the only such NIC on the box — if a second Aquantia adapter is ever added, disambiguate with `ATTRS{subsystem_vendor}`/`ATTRS{subsystem_device}` rather than reverting to MAC.
