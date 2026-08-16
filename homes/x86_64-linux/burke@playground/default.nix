{ pkgs, ... }:
{
  t11s = {
    enable = true;
    personal.enable = true;
    neovim.enable = true;
    shell.enable = true;
  };
  stylix.base16Scheme = "${pkgs.base16-schemes}/share/themes/equilibrium-light.yaml";
  home.stateVersion = "26.05";
}
