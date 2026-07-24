{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.eternal-terminal;
in
{
  options.t11s.eternal-terminal = with lib; {
    enable = mkEnableOption "Eternal Terminal (et) client";
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.eternal-terminal ];
    home.sessionVariables.ET_NO_TELEMETRY = "1";
  };
}
