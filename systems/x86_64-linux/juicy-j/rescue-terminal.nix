# A session for getting in over the pikvm when ssh is not an option.
{ lib, pkgs, ... }:
let
  # win+enter never reaches the box over the kvm, so this needs no modifiers:
  # one fullscreen terminal under cage, with ghostty's own ctrl+shift splits.
  rescueDesktop = pkgs.writeText "rescue.desktop" ''
    [Desktop Entry]
    Name=Rescue Terminal
    Comment=Fullscreen terminal reachable over the KVM
    Exec=${lib.getExe pkgs.cage} -- ${lib.getExe pkgs.ghostty}
    Type=Application
    DesktopNames=rescue
  '';
  rescueSession =
    pkgs.runCommandLocal "rescue-session"
      {
        passthru.providedSessions = [ "rescue" ];
      }
      ''
        mkdir -p $out/share/wayland-sessions
        cp ${rescueDesktop} $out/share/wayland-sessions/rescue.desktop
      '';
in
{
  services.displayManager.sessionPackages = [ rescueSession ];
}
