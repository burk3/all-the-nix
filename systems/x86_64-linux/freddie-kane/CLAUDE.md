# freddie-kane

Framework 13 (AMD 7040) laptop. Uses **juicy-j as a remote builder** — most builds for this host execute on juicy-j and stream back. If juicy-j is unreachable, builds fall back to local and slow down dramatically.

## Disk / boot

- **Declarative layout** in `disko.nix`: single NVMe, GPT → ESP (`/boot`), `cryptswap` (64G LUKS2 → swap, hibernate resume), `cryptroot` (rest, LUKS2 → btrfs subvols `@`,`@home`,`@nix`, zstd). disko generates `fileSystems`/`swapDevices`/`boot.initrd.luks.devices`; **don't** add those by hand.
- **Encryption**: block-level LUKS2 (so it's compatible with lanzaboote Measured Boot). Boots via LUKS passphrase until TPM2+PIN is enrolled.
- **Secure Boot + Measured Boot** are gated behind `secureBoot` (a `let` binding in `default.nix`), default **false**. lanzaboote can't sign the boot chain before its sbctl keys exist, so a fresh install boots with **systemd-boot + passphrase**; you turn on lanzaboote + `measuredBoot` (systemd-pcrlock, PCRs 0/4/7) on a later rebuild. This replaces the old `ensure-pcr`/`systemIdentity` PCR-15 check (deleted).

## Reinstall runbook

The installer is a **minimal** live system built by the `t11s.forRealInstaller`
module (`modules/nixos/for-real-installer`) and exposed as
`config.system.build.for-real-installer-iso`. It is *not* freddie-kane extended
with the CD profile (that leaks freddie's `resumeDevice`/LUKS units into the live
boot and hangs). Instead it bakes freddie-kane's whole toplevel closure onto the
medium, so the install is fully offline — `nixos-install --system <toplevel>`
just copies store paths locally; no flake, no network, no cache.

1. **Build the ISO** (on juicy-j — it's multi-GB, the full freddie closure):
   ```sh
   nix build .#nixosConfigurations.freddie-kane.config.system.build.for-real-installer-iso
   ```
   Flash `result/iso/*.iso` to USB.

2. **Install.** Boot the USB → plain shell. One command:
   ```sh
   sudo install-for-real
   ```
   It confirms, runs the disko script (wipes the disk per `disko.nix`, prompts for
   the LUKS passphrase, mounts at `/mnt`), `nixos-install --system <baked
   toplevel>`, then prompts (via `nixos-enter … passwd`) to set a login password
   for the main user (root stays locked; the user is in `wheel` for sudo). Reboot.

3. **First boot.** Unlock with the passphrase, log in as the main user. You're on
   systemd-boot, no Secure Boot, no TPM yet. Clone the repo to your work dir.

4. **Enable Secure Boot.**
   ```sh
   sudo sbctl create-keys                       # keys -> /var/lib/sbctl
   # reboot into firmware, put it in Secure Boot *Setup Mode* (clear keys), then:
   sudo sbctl enroll-keys --microsoft           # keep MS keys so firmware/option ROMs still verify
   ```
   Flip `secureBoot = true` in `default.nix`, then:
   ```sh
   sudo nixos-rebuild boot --flake .#freddie-kane
   ```
   This switches to lanzaboote, signs the boot chain, and (because `measuredBoot.enable`) builds the systemd-pcrlock policy at `/var/lib/systemd/pcrlock.json`. Reboot; confirm Secure Boot is active (`sbctl status` / `bootctl status`).

5. **Enroll TPM2 + PIN** against the pcrlock policy, for **both** LUKS devices (root and swap, so hibernate-resume can unlock too):
   ```sh
   # sanity check — note systemd-pcrlock lives in systemd's libexec, not on $PATH:
   /run/current-system/systemd/lib/systemd/systemd-pcrlock is-supported   # expect: yes
   # the policy lanzaboote wrote during the secureBoot `nixos-rebuild boot` must exist;
   # if missing, re-run `sudo nixos-rebuild boot --flake .#freddie-kane` to generate it:
   ls -l /var/lib/systemd/pcrlock.json

   # systemd-cryptenroll IS on $PATH. Enroll both LUKS devices (root + swap):
   for m in cryptroot cryptswap; do
     dev=$(cryptsetup status "$m" | awk '$1=="device:"{print $2}')   # backing LUKS partition
     sudo systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=true \
       --tpm2-pcrlock=/var/lib/systemd/pcrlock.json "$dev"
   done
   ```
   Keep the passphrase slot as recovery. From here, lanzaboote re-seals the policy on every `nixos-rebuild`, so kernel/generation updates don't lock you out.

> If a TPM/pcrlock change ever drops you to an emergency shell, the passphrase keyslot still unlocks both volumes.
