{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.internalCA;
  sshHostKey =
    (lib.findFirst (
      key: key.type == "ed25519"
    ) "/etc/ssh/ssh_host_ed25519_key" config.services.openssh.hostKeys).path;
  sshHostCert = "${sshHostKey}-cert.pub";
in
{
  options.t11s.internalCA = {
    enable = lib.mkEnableOption "trust the tactilecactus internal CA";
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        security.pki.certificateFiles = [ ./root_ca.crt ];
        environment.systemPackages = [ pkgs.step-cli ];

        # configure openssh server
        # make sure we're using an ed25519 host key

        services.openssh.extraConfig = ''
          HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub
        '';
        services.openssh.settings.TrustedUserCAKeys = "${pkgs.writeText "step-ssh-user-ca" ''
          ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHZCFIjXZy8mmZIrGVq4uSHBHKTwj3RG+ewTgCB+zRgv6V2zG43+U5RLhkLfHsDA8x/Lr16ELePSVNBEPKujQdk=
        ''}";

        # configure ssh client to trust certs from my ca
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
            hostNames = [
              "*.t11s.net"
              "*.lan"
              "*.dab-ling.ts.net"
            ];
            publicKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBlVBdw/8ynhdjvzUSzIFcIenCnEhGw1kVmAVfY41uWFF4N8p1ZrkSRSIKNzN1gem+lzY5LxSeAnnpI8c54xnnA=";
          };
        };
      }
      (lib.mkIf config.services.openssh.enable {

        # Renew ssh host key cert
        systemd.services.step-ssh-renew = {
          description = "Renew SSH host certificate via step-ca";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.t11s.t11s-step}/bin/t11s-step ssh renew ${sshHostCert} ${sshHostKey} --force";
            ExecStartPost = "${pkgs.systemd}/bin/systemctl reload sshd.service";
            # step needs to find the CA root + config
          };
          after = [
            "network-online.target"
            "time-sync.target"
          ];
          wants = [
            "network-online.target"
            "time-sync.target"
          ];
        };

        systemd.timers.step-ssh-renew = {
          description = "Renew SSH host certificate periodically";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5m";
            OnUnitActiveSec = "1h";
            RandomizedDelaySec = "10m";
            Persistent = true;
          };
        };
      })
    ]
  );
}
