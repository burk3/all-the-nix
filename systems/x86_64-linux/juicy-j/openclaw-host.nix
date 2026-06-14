{ pkgs, ... }:
{
  # Host enablement for the OpenClaw agent VM (guest defined in ~/src/openclaw-vm).
  # juicy-j only provides the perimeter: libvirt + virtiofs + host dirs. The guest
  # itself is a mutable Debian VM managed out-of-band via cloud-init.

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      runAsRoot = false;
      # Provide virtiofsd so domains can use <filesystem driver type="virtiofs">.
      vhostUserPackages = [ pkgs.virtiofsd ];
    };
  };

  # juicy-j uses nftables; have libvirt manage its NAT/forward rules via the
  # nftables backend rather than legacy iptables.
  environment.etc."libvirt/network.conf".text = ''
    firewall_backend = "nftables"
  '';

  # Manage VMs without sudo.
  users.users.burke.extraGroups = [ "libvirtd" ];

  # The guest reaches libvirt's dnsmasq (DHCP + DNS) over the NAT bridge. juicy-j's
  # default-drop nftables firewall would otherwise drop those host-bound packets,
  # so the guest never gets a lease. Trust the NAT bridge (matches the bridge name
  # in openclaw-vm/network.xml).
  networking.firewall.trustedInterfaces = [ "virbr-ocnat" ];

  # Host-side directory the guest mounts over virtiofs:
  #   - workspace: read/write agent working files, visible on the host
  # Secrets are NOT host-managed: OpenClaw's creds live in an env file on the
  # guest's persistent data disk (see openclaw-vm), so there's no decrypted-secret
  # share on the host. Revisit agenix here only if a host-authoritative secret is
  # ever needed.
  systemd.tmpfiles.rules = [
    "d /srv/openclaw 0755 root root - -"
    "d /srv/openclaw/workspace 0775 burke libvirtd - -"
  ];

  environment.systemPackages = [ pkgs.virtiofsd ];
}
