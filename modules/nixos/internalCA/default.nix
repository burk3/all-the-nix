{config, lib, pkgs, ... }:
let cfg = config.t11s.internalCA; in
{
  options.t11s.internalCA = {
    enable = lib.mkEnableOption "trust the tactilecactus internal CA";
  };
  config = lib.mkIf cfg.enable {
    security.pki.certificateFiles = [ ./root_ca.crt ];
    environment.systemPackages = [ pkgs.step-cli ];
  };
}
