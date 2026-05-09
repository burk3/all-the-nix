{ config, lib, pkgs, namespace, ... }:
let cfg = config.${namespace}.helix; in
{
  options.${namespace}.helix.enable = lib.mkEnableOption "enable helix with some fun defaults";
  config = lib.mkIf cfg.enable {
    programs.helix = {
      enable = true;
      package = pkgs.evil-helix;
      settings = {
        editor.indent-guides.render = true;
        editor.auto-pairs = true;
        editor.bufferline = "multiple";
        editor.true-color = true;
        editor.whitespace.characters = {
          tab = "⇥";
          trailing = "·";
        };
      };
      extraPackages = with pkgs; [ nil ];
    };
  };
}
