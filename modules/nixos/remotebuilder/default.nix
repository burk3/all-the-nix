{ config, lib, pkgs, ... }:
let
  cfg = config.t11s.remotebuild;
in
with lib;
{
  options.t11s.remotebuild = with types; {
    serveBuilds = mkOption {
      type = bool;
      default = false;
      description = "enable remotebuild user with key to enable this system to remote build";
    };
    hosts = mkOption {
      type = nullOr (listOf str);
      default = null;
      description = "list of hostnames (on tailscale prolly) that will remote build";
    };
  };
  config =
    let
      mkIfServing = mkIf cfg.serveBuilds;
      mkIfRemotes = mkIf (cfg.hosts != null);
    in
    {
      users.users.remotebuild = mkIfServing {
        isNormalUser = true;
        createHome = false;
        group = "remotebuild";

        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBIEsaehwxAc2Bz4XGSn6ab46TypW4v/Bt2ZrhUO3dBm root@freddie-kane"
        ];
      };

      users.groups.remotebuild = mkIfServing { };

      nix.settings.trusted-users = mkIfServing [ "remotebuild" ];

      # client stuff
      nix.distributedBuilds = mkIfRemotes true;
      nix.settings.builders-use-substitutes = mkIfRemotes true;

      nix.buildMachines = mkIfRemotes (
        map (hostname: {
          hostName = hostname;
          sshUser = "remotebuild";
          sshKey = "/root/.ssh/remotebuild";
          system = pkgs.stdenv.hostPlatform.system;
          supportedFeatures = [
            "nixos-test"
            "big-parallel"
            "kvm"
          ];
        }) cfg.hosts
      );
    };
}
