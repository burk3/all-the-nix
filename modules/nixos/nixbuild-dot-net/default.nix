{ config, lib, ... }:
let
  cfg = config.t11s.nixbuild-dot-net;
in
with lib;
{
  options.t11s.nixbuild-dot-net = {
    enable = mkEnableOption "nixbuild.net as an aarch64-linux remote builder";
  };
  config = mkIf cfg.enable {
    age.secrets."nixbuild-dot-net.ssh-key".file = ../../../secrets/nixbuild-dot-net.ssh-key.age;

    nix.distributedBuilds = true;
    nix.buildMachines = [
      {
        hostName = "eu.nixbuild.net";
        system = "aarch64-linux";
        maxJobs = 100;
        supportedFeatures = [
          "benchmark"
          "big-parallel"
        ];
        protocol = "ssh-ng";
        sshKey = config.age.secrets."nixbuild-dot-net.ssh-key".path;
        # base64 of eu.nixbuild.net's ssh-ed25519 host key
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVBJUUNaYzU0cG9KOHZxYXdkOFRyYU5yeVFlSm52SDFlTHBJRGdiaXF5bU0=";
      }
    ];
  };
}
