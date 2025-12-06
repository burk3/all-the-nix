{
  config,
  lib,
  ...
}:
let
  cfg = config.t11s.git;
in
{
  options.t11s.git = with lib; {
    enable = mkEnableOption "Enable t11s";
  };
  config = lib.mkIf cfg.enable {
    programs.git = {
      enable = true;
      ignores = [
        ".envrc"
        ".direnv"
        ".venv"
      ];
      settings.init.defaultBranch = "master";
      settings.alias.co = "checkout";
      settings.alias.st = "status";
      settings.alias.lg = "log --graph --decorate --oneline";
    };
    programs.delta.enable = true;
  };
}
