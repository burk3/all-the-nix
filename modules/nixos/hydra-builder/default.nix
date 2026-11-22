{
  config,
  lib,
  ...
}:
let
  cfg = config.t11s.hydraBuilder;
in
with lib;
{
  options.t11s.hydraBuilder = {
    enable = mkEnableOption "a Hydra build agent for juicy-j's queue runner, authenticated by this host's agenix token";
    queueRunnerAddr = mkOption {
      type = types.str;
      default = "http://juicy-j.lan:50051";
      description = "gRPC endpoint of the queue runner (services.hydra.queueRunner.grpc on juicy-j)";
    };
  };

  config = mkIf cfg.enable {
    # secrets/hydra-builder-<host>.token.age; juicy-j's queue runner lists the
    # same file in its tokenPaths. The builder runs as hydra-builder:hydra.
    age.secrets.hydra-builder-token = {
      file = ../../../secrets/hydra-builder-${config.networking.hostName}.token.age;
      group = "hydra";
      mode = "0440";
    };

    services.hydra-builder = {
      enable = true;
      inherit (cfg) queueRunnerAddr;
      authorizationFile = config.age.secrets.hydra-builder-token.path;
    };
  };
}
