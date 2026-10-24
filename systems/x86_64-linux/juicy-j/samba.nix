{ ... }:
let
  lan = "10.1.1.0/24";
in
{
  # LAN-only SMB share for one-off Windows backups. Guest access is mapped to
  # burke via `force user`, so everything written lands as burke:users and the
  # share dir needs no special permissions.
  services.samba = {
    enable = true;
    nmbd.enable = false; # no NetBIOS browsing; connect by \\10.1.1.20\a16bkp
    winbindd.enable = false;
    settings = {
      global = {
        "server string" = "juicy-j";
        "server min protocol" = "SMB2_10";
        "hosts allow" = "${lan} 127.0.0.1";
        "hosts deny" = "0.0.0.0/0";
        "map to guest" = "Bad User";
        "guest account" = "nobody";
        "load printers" = "no";
        "printing" = "bsd";
        "printcap name" = "/dev/null";
        "disable spoolss" = "yes";
      };
      a16bkp = {
        path = "/srv/smb/a16bkp";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "force user" = "burke";
        "force group" = "users";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };
  };

  # Not openFirewall: that would open 445 on every interface (incl. tailscale).
  networking.firewall.extraInputRules = ''
    ip saddr ${lan} tcp dport 445 accept
  '';
}
