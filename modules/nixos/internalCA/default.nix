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
  dot1xDir = "/var/lib/t11s-8021x";
  dot1xCert = "${dot1xDir}/client.crt";
  dot1xKey = "${dot1xDir}/client.key";
  dot1xGroup = "wpa_supplicant";
  dot1xFixPerms = pkgs.writeShellScript "t11s-8021x-perms" ''
    ${pkgs.coreutils}/bin/chown root:${dot1xGroup} ${dot1xCert} ${dot1xKey}
    ${pkgs.coreutils}/bin/chmod 0640 ${dot1xCert} ${dot1xKey}
  '';
in
{
  options.t11s.internalCA = {
    enable = lib.mkEnableOption "trust the tactilecactus internal CA";
    dot1x = {
      enable = lib.mkEnableOption "an 802.1x (EAP-TLS) client cert from the devices provisioner, renewed daily";
      class = lib.mkOption {
        type = lib.types.enum [
          "personal"
          "work"
        ];
        default = "personal";
        description = "Cert OU; RADIUS on turing maps personal -> VLAN 100, work -> VLAN 300.";
      };
    };
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

        # First signing of the host key, and re-signing after the cert has
        # expired (the CA does not renew expired certs). Prompts for the
        # burke@t11s.net provisioner password. The renewal timer below takes
        # over from there.
        environment.systemPackages = [
          (pkgs.writeShellApplication {
            name = "t11s-sign-host-key";
            runtimeInputs = [
              pkgs.t11s.t11s-step
              pkgs.openssh
            ];
            text = ''
              if [[ $EUID -ne 0 ]]; then
                echo "the host key is only readable by root: sudo t11s-sign-host-key" >&2
                exit 1
              fi
              host=${config.networking.hostName}
              t11s-step ssh certificate --host --sign --force \
                --provisioner burke@t11s.net \
                --principal "$host.lan" \
                --principal "$host.dab-ling.ts.net" \
                "$host.t11s.net" ${sshHostKey}.pub
              ssh-keygen -L -f ${sshHostCert}
              systemctl reload sshd.service
            '';
          })
        ];

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
      (lib.mkIf cfg.dot1x.enable {
        # Stable path for NetworkManager's 802-1x.ca-cert.
        environment.etc."t11s-8021x/root_ca.crt".source = ./root_ca.crt;

        # NixOS runs wpa_supplicant as its own unprivileged user, and that's
        # what opens the cert + key (not NetworkManager), so its group needs read.
        systemd.tmpfiles.rules = [ "d ${dot1xDir} 0750 root ${dot1xGroup} -" ];

        # It also runs chrooted (RootDirectory=/run/wpa_supplicant) with only
        # /nix/store and /etc bound in, so /var/lib isn't visible at all.
        systemd.services.wpa_supplicant =
          lib.mkIf
            (
              config.networking.wireless.enable
              || (
                config.networking.networkmanager.enable
                && config.networking.networkmanager.wifi.backend == "wpa_supplicant"
              )
            )
            {
              serviceConfig.BindReadOnlyPaths = [ "-${dot1xDir}" ];
            };

        # First issuance, and re-issuing after the cert has expired (renewal
        # can't revive an expired cert). Prompts for the devices provisioner
        # password. The renewal timer below takes over from there.
        environment.systemPackages = [
          (pkgs.writeShellApplication {
            name = "t11s-sign-8021x";
            runtimeInputs = [ pkgs.t11s.t11s-step ];
            text = ''
              if [[ $EUID -ne 0 ]]; then
                echo "the 802.1x key is root-only: sudo t11s-sign-8021x" >&2
                exit 1
              fi
              install -d -m 0750 -o root -g ${dot1xGroup} ${dot1xDir}
              t11s-step ca certificate --force \
                --provisioner devices \
                --set class=${cfg.dot1x.class} \
                --not-after 8760h \
                ${config.networking.hostName} ${dot1xCert} ${dot1xKey}
              ${dot1xFixPerms}
              t11s-step certificate inspect --short ${dot1xCert}
            '';
          })
        ];

        # Renews once the cert is within 30 days of expiry. NetworkManager
        # re-reads the files on its next (re)association; the old cert stays
        # valid until then, so no reconnect is forced.
        systemd.services.t11s-8021x-renew = {
          description = "Renew 802.1x client certificate via step-ca";
          unitConfig.ConditionPathExists = dot1xCert;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.t11s.t11s-step}/bin/t11s-step ca renew --force --expires-in 720h ${dot1xCert} ${dot1xKey}";
            ExecStartPost = dot1xFixPerms;
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

        systemd.timers.t11s-8021x-renew = {
          description = "Renew 802.1x client certificate periodically";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5m";
            OnUnitActiveSec = "1d";
            RandomizedDelaySec = "1h";
            Persistent = true;
          };
        };
      })
    ]
  );
}
