{
  config,
  lib,
  ...
}:
let
  cfg = config.t11s.remotebuild;
  # Builders by short name. `addresses` holds one name per network; each
  # client reaches every builder by the one for its `network`. Host certs carry
  # both names as principals, and pinned keys are keys, not names.
  hostConfigs = {
    juicy-j = {
      addresses = {
        lan = "juicy-j.lan";
        tailnet = "juicy-j.dab-ling.ts.net";
      };
      maxJobs = 32;
      speedFactor = 4;
      system = "x86_64-linux";
      # base64 of the ssh-ed25519 host key (same key as root@juicy-j in agenix-rules.nix)
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU9xQ2ltU0FOUWw5UVl4RG5rd2lBblUrbUpHWU1kd3dNRGNwRlVKRkJhdEw=";
      supportedFeatures = [
        "nixos-test"
        "big-parallel"
        "kvm"
        "uid-range"
      ];
    };
    swaine = {
      addresses = {
        lan = "swaine.lan";
        tailnet = "swaine.dab-ling.ts.net";
      };
      maxJobs = 12; # its CPU count
      speedFactor = 2;
      system = "aarch64-linux";
      # Not pinned: swaine's host key is signed by the t11s CA
      # (t11s-sign-host-key), which every client trusts for *.lan and
      # *.dab-ling.ts.net through ssh_known_hosts (see the internalCA module).
      publicHostKey = null;
      # /dev/kvm is there under mainline (checked from the stock ISO)
      supportedFeatures = [
        "nixos-test"
        "big-parallel"
        "kvm"
        "uid-range"
      ];
    };
  };
  # Clients that may build here, as the remotebuild user: root on each client
  # (key at /root/.ssh/remotebuild) and juicy-j's Hydra queue runner.
  clientKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBIEsaehwxAc2Bz4XGSn6ab46TypW4v/Bt2ZrhUO3dBm root@freddie-kane"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDIj01SWmT0epSkhhyK5L29ojolctN9mR+EDHbM/o2Hh root@juicy-j"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPqCGEOVzu/h5eTCfwNXG62H9Q44Mk0q4Dqu41E/F/L6 hydra-queue-runner@juicy-j"
  ];
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
      type = nullOr (listOf (enum (attrNames hostConfigs)));
      default = null;
      description = "builders (short names from hostConfigs) this host delegates builds to";
    };
    network = mkOption {
      type = enum [
        "lan"
        "tailnet"
      ];
      # laptops roam; everything else sits on the home LAN with the builders
      default = if config.t11s.systemType == "laptop" then "tailnet" else "lan";
      defaultText = literalExpression ''if systemType == "laptop" then "tailnet" else "lan"'';
      description = "which of each builder's addresses this host uses";
    };
  };
  config =
    let
      mkIfServing = mkIf cfg.serveBuilds;
      mkIfRemotes = mkIf (cfg.hosts != null);
      builders = map (
        name: hostConfigs.${name} // { hostName = hostConfigs.${name}.addresses.${cfg.network}; }
      ) cfg.hosts;
    in
    {
      users.users.remotebuild = mkIfServing {
        isNormalUser = true;
        createHome = false;
        group = "remotebuild";
        # nothing lives there; this also quiets sshd's "Could not chdir" on login
        home = "/var/empty";

        openssh.authorizedKeys.keys = clientKeys;
      };

      users.groups.remotebuild = mkIfServing { };

      nix.settings.trusted-users = mkIfServing [ "remotebuild" ];

      # client stuff
      nix.distributedBuilds = mkIfRemotes true;
      nix.settings.builders-use-substitutes = mkIfRemotes true;

      # Also substitute from the builders, with the same user and key. Their
      # stores are unsigned, so `trusted=true` is what lets the daemon accept
      # paths from them; it is scoped to these stores only.
      nix.settings.substituters = mkIfRemotes (
        map (
          b:
          "ssh-ng://remotebuild@${b.hostName}?ssh-key=/root/.ssh/remotebuild&trusted=true${
            optionalString (b.publicHostKey != null) "&base64-ssh-public-host-key=${b.publicHostKey}"
          }"
        ) builders
      );
      # Nix shells out to OpenSSH for builders and ssh-ng substituters. Without
      # a connect timeout an unreachable builder (laptop off the tailnet)
      # stalls every build. Set in ssh_config so it covers the daemon and root
      # alike; mkAfter keeps these Host blocks at the end of the file so no
      # other module's global options land inside them.
      programs.ssh.extraConfig = mkIfRemotes (
        mkAfter (
          concatMapStrings (b: ''
            Host ${b.hostName}
              ConnectTimeout 5
          '') builders
        )
      );

      nix.buildMachines = mkIfRemotes (
        map (b: {
          inherit (b)
            hostName
            maxJobs
            speedFactor
            system
            publicHostKey
            supportedFeatures
            ;
          protocol = "ssh-ng";
          sshUser = "remotebuild";
          sshKey = "/root/.ssh/remotebuild";
        }) builders
      );
    };
}
