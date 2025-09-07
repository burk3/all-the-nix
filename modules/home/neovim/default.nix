{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.t11s.neovim;
in
with lib;
{
  options.t11s.neovim = {
    enable = mkEnableOption "Enable neovim with the config";
  };
  config = mkIf cfg.enable {
    home.packages = [ pkgs.nil ];
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
      vimdiffAlias = true;
      plugins = with pkgs.vimPlugins; [
        gundo-vim
        nerdtree
        vim-surround
        {
          plugin = lightline-vim;
          config = "let g:lightline = {'colorscheme': 'catppuccin'}";
        }
        vim-markdown
        nvim-treesitter.withAllGrammars
        vim-nix
        {
          plugin = nvim-lspconfig;
          config = ''
            lua require'lspconfig'.nil_ls.setup{}
          '';
        }
      ];
      extraConfig = ''
        " sane backspaces
        set backspace=2
        " sane tabs/indentation
        set ts=2
        set sw=2
        set expandtab
        set smartindent
        set autoindent
        " show all that whitespace by default
        set listchars=trail:·,precedes:«,extends:»,eol:↲,tab:⇥\
        " set list
        " i mostly use marker folds
        set foldmethod=marker
      '';
    };
  };
}
