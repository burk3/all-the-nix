{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.t11s.shell;
in
with lib;
{
  options.t11s.shell = {
    enable = mkEnableOption "Enable standard shell configuration";
    wsl = mkOption {
      description = "configure wsl-specific things like the starship windows executable path";
      type = types.bool;
      default = false;
    };
  };
  config = mkIf cfg.enable {
    home.packages = with pkgs; [ zsh-completions ];

    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
      config = {
        global.hide_env_diff = true;
      };
    };

    programs.bash.enable = true;

    programs.zsh = {
      enable = true;
      history.size = 10000;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
      autosuggestion = {
        enable = true;
        strategy = [
          "match_prev_cmd"
          "completion"
        ];
      };
      initContent = ''
        set -k # INTERACTIVE_COMMENTS
        source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
      '';
    };

    programs.starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      settings = {
        add_newline = true;
        format = lib.concatStrings [
          "$username"
          "$hostname"
          "$nix_shell"
          "$directory"
          "$git_branch"
          "$git_state"
          "$git_status"
          "$cmd_duration"
          "$line_break"
          "$python"
          "$rust"
          "$character"
        ];
        character = {
          error_symbol = "[❯](red)";
          success_symbol = "[❯](purple)";
          vimcmd_symbol = "[❮](green)";
        };
        cmd_duration = {
          format = "[$duration]($style) ";
          style = "yellow";
        };
        directory = {
          style = "blue";
        };
        git_state = {
          format = "\\([$state( $progress_current/$progress_total)]($style)\\) ";
          style = "bright-black";
        };
        python = {
          format = "[$virtualenv]($style) ";
        };
        rust = {
          format = "[$symbol($version )]($style)";
        };
        git_status.windows_starship = mkIf cfg.wsl "${pkgs.t11s.starship-win}/bin/starship.exe";
      };
    };
  };
}
