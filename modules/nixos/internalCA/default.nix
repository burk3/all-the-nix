{config, lib, pkgs, ... }:
let cfg = config.t11s.internalCA; in
{
  options.t11s.internalCA = {
    enable = lib.mkEnableOption "trust the tactilecactus internal CA";
  };
  config = lib.mkIf cfg.enable {
    security.pki.certificateFiles = [ ./root_ca.crt ];
    environment.systemPackages = [ pkgs.step-cli ];
    services.openssh.extraConfig = ''
      HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub
    '';
    services.openssh.settings.TrustedUserCAKeys = "${pkgs.writeText "step-ssh-user-ca" ''
      ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHZCFIjXZy8mmZIrGVq4uSHBHKTwj3RG+ewTgCB+zRgv6V2zG43+U5RLhkLfHsDA8x/Lr16ELePSVNBEPKujQdk=
    ''}";
    # fix for some dumb ssh config gen
    programs.ssh.systemd-ssh-proxy.enable = false;
    programs.ssh.extraConfig = ''
      CanonicalizeHostname yes
      CanonicalDomains dab-ling.ts.net t11s.net lan
      CanonicalizeFallbackLocal yes
      CanonicalizeMaxDots 0
    '';
    programs.ssh.knownHosts = {
      "t11s.net" = {
        certAuthority = true;
        hostNames = [ "*.t11s.net" "*.lan" "*.dab-ling.ts.net" ];
        publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBlVBdw/8ynhdjvzUSzIFcIenCnEhGw1kVmAVfY41uWFF4N8p1ZrkSRSIKNzN1gem+lzY5LxSeAnnpI8c54xnnA=";
      };
    };
  };
}
