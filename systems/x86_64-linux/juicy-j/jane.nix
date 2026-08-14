{ pkgs, ... }:
{
  # Read-only debug account for Jane, the OpenClaw agent running in the guest VM
  # (see openclaw-host.nix). The agent needs to look at juicy-j's journal and
  # service state to diagnose lemonade / AI-stack problems on its own instead of
  # relaying every question through a human.
  #
  # Deliberately NOT granted: wheel/sudo, nix trusted-user, libvirtd, docker.
  # This account can observe the machine; it cannot change it. Everything it can
  # reach is readable-only, so the worst case is disclosure, not damage.
  users.users.jane = {
    isNormalUser = true;
    description = "Jane (OpenClaw agent) - read-only debugging";
    shell = pkgs.bash;
    # Key-only: no password, no console/su login path.
    hashedPassword = "!";
    extraGroups = [
      "systemd-journal" # journalctl for all units, not just its own
      "adm" # legacy logs under /var/log
      "lemonade" # lemond's state dir (models, caches) - see tmpfiles below
      "video" # GPU/NPU device nodes: amd-smi, rocm-smi, npu telemetry
      "render"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHHi8S44u2DPy1RXpUxClq6oSXFFCSOIHiTuXVtINT5h jane@openclaw"
    ];
  };

  # `createHome` on the lemonade account leaves /var/lib/lemonade at 0700, which
  # would make the group membership above purely decorative. Widen the top-level
  # dir to group-read so jane can see what models/config lemond actually loaded.
  # Non-recursive on purpose: this does not touch the weights underneath.
  systemd.tmpfiles.rules = [
    "z /var/lib/lemonade 0750 lemonade lemonade - -"
  ];
}
