{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.t11s.wsl;
  sshRelayInitFish = ''
    set -gx SSH_AUTH_SOCK $HOME/.ssh/agent.sock
    ss -a | grep -q $SSH_AUTH_SOCK
    if test $status -ne 0
        rm -f "''${SSH_AUTH_SOCK}"
        begin
            setsid ${pkgs.socat}/bin/socat UNIX-LISTEN:"''${SSH_AUTH_SOCK},fork" EXEC:"${pkgs.t11s.npiperelay-win}/bin/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork &
        end >/dev/null 2>&1
    end
  '';
  sshRelayInitSh = ''
    export SSH_AUTH_SOCK=''${HOME}/.ssh/agent.sock
    ss -a | grep -q "''${SSH_AUTH_SOCK}"
    if [ $? -ne 0 ]; then
      rm -f "''${SSH_AUTH_SOCK}"
      ( setsid ${pkgs.socat}/bin/socat UNIX-LISTEN:''${SSH_AUTH_SOCK},fork EXEC:"${pkgs.t11s.npiperelay-win}/bin/npiperelay.exe -ei -s //./pipe/openssh-ssh-agent",nofork & ) >/dev/null 2>&1
    fi
  '';

in
with lib;
{
  options.t11s.wsl = with types; {
    enable = mkEnableOption "Enable WSL-specific features";
    useWindowsSshAgent = mkOption {
      description = "setup npiperelay.exe and socat to use the SSH agent running on the Windows side for most shells";
      type = bool;
      default = true;
    };
    starshipGitStatus = mkOption {
      description = "configure `git_status.windows_starship` to use a provided `starship.exe` so you don't have to install on your own";
      type = bool;
      default = true;
    };
  };

  config = mkIf cfg.enable {
    # shell setup for ssh agent relay
    programs.bash.profileExtra = mkIf cfg.useWindowsSshAgent sshRelayInitSh;
    programs.zsh.profileExtra = mkIf cfg.useWindowsSshAgent sshRelayInitSh;
    programs.fish.shellInit = mkIf cfg.useWindowsSshAgent sshRelayInitFish;

    # set up starship
    programs.starship.settings.git_status.windows_starship =
      mkIf cfg.starshipGitStatus "${pkgs.t11s.starship-win}/bin/starship.exe";
  };
}
