{ pkg, config, lib, ... }:
let
  cfg = config.t11s.git;
in
{
  options = with lib; {
    enable = mkEnableOption "Enable t11s";
  };
  config = lib.mkIf cfg.enable {
    programs.git = {
      enable = true;
      delta.enable = true;
      ignores = [
        ".envrc"
        ".direnv"
        ".venv"
      ];
      extraConfig.init.defaultBranch = "master";
      aliases.co = "checkout";
      aliases.st = "status";
      aliases.lg = "log --graph --decorate --oneline";
    };
  };
}