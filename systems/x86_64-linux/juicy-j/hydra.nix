{ pkgs, ... }:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
  };

  services.hydra = {
    enable = true;
    listenHost = "127.0.0.1";
    port = 3001;
    hydraURL = "https://hydra.ts.t11s.net";
    notificationSender = "hydra@juicy-j.lan";
    useSubstitutes = true;
  };

  # nixbuild.net offload for aarch64 builds. The SSH key at
  # /root/.ssh/nixbuild-dot-net is provisioned out-of-band (same one used on
  # freddie-kane).
  nix.distributedBuilds = true;
  nix.settings.substituters = [ "ssh://eu.nixbuild.net?priority=100" ];
  nix.settings.trusted-public-keys = [
    "nixbuild.net/GLER5I-1:2UGRxSmQWU22LD27+UepgZlASKaFyk4YOwXoH/Wln9U="
  ];
  nix.buildMachines = [
    {
      hostName = "localhost";
      # Build locally without SSH. With the default protocol = "ssh", the module
      # renders this as `ssh://localhost` in /etc/nix/machines, which Hydra
      # tolerates but breaks interactive `nix build` (the CLI shares this file
      # via builders=@/etc/nix/machines and tries to SSH into itself). A bare
      # `localhost` entry (protocol = null) builds on the local machine — the
      # form nixpkgs documents as "used by hydra".
      protocol = null;
      systems = [ "x86_64-linux" ];
      supportedFeatures = [
        "kvm"
        "big-parallel"
        "nixos-test"
        "benchmark"
      ];
      maxJobs = 16;
    }
    {
      hostName = "eu.nixbuild.net";
      system = "aarch64-linux";
      maxJobs = 100;
      supportedFeatures = [
        "benchmark"
        "big-parallel"
      ];
      sshKey = "/root/.ssh/nixbuild-dot-net";
    }
  ];

  services.caddy = {
    enable = true;
    globalConfig = ''
      acme_ca https://turing.lan/acme/acme/directory
    '';
    virtualHosts."hydra.ts.t11s.net, hydra.lan".extraConfig = ''
      tls {
        issuer acme {
          disable_http_challenge
        }
      }
      reverse_proxy 127.0.0.1:3001
    '';
  };

  networking.firewall.allowedTCPPorts = [ 443 ];
}
