{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.wslSSHAgent;
in
with lib;
{
  options.t11s.wslSSHAgent.enable = mkEnableOption "use the ssh agent from windows inside wsl!";
  config =
    let
      npiperelay = pkgs.fetchzip {
        url = "https://github.com/jstarks/npiperelay/releases/download/v0.1.0/npiperelay_windows_amd64.zip";
      };
      wslInit = ''
        export SSH_AUTH_SOCK=''${HOME}/.ssh/agent.sock
        ss -a | grep -q "''${SSH_AUTH_SOCK}"
        if [ $? -ne 0 ]; then
          rm -f "''${SSH_AUTH_SOCK}"
          ( setsid ${pkgs.socat}/bin/socat UNIX-LISTEN:''${SSH_AUTH_SOCK},fork EXEC:"${pkgs.t11s.npiperelay-win}/bin/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork & ) >/dev/null 2>&1
        fi
      '';
    in
    mkIf cfg.enable {
      programs.zsh.profileExtra = wslInit;
      programs.bash.profileExtra = wslInit;
    };
}
