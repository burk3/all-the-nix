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
    programs.neovim = {
      enable = true;
      package = pkgs.unstable.neovim-unwrapped;
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
        # {
        #   plugin = nvim-lspconfig;
        #   config = ''
        #     lua require'lspconfig'.nil_ls.setup{}
        #   '';
        # }
        vim-tidal
        pkgs.unstable.vimPlugins.haskell-tools-nvim
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

        lua << EOF
          vim.g.mapleader = ' '

          vim.diagnostic.config({ virtual_lines = { current_line = true } })

          vim.lsp.config['nil'] = {
            cmd = { '${pkgs.nil}/bin/nil' },
            filetypes = { 'nix' },
            root_markers = { 'flake.nix' },
          }
          vim.lsp.enable('nil')

          vim.keymap.set('n', '<leader>f', function()
            vim.lsp.buf.format({ async = false })
          end, { desc = 'Format buffer (LSP)' })

          vim.keymap.set('n', '<leader>d', function()
            if vim.diagnostic.config().virtual_lines then
              vim.diagnostic.config({ virtual_lines = false })
            else
              vim.diagnostic.config({ virtual_lines = { current_line = true } })
            end
          end, { desc = 'Toggle diagnostic virtual_lines' })

          vim.api.nvim_create_autocmd('BufWritePre', {
            pattern = { '*.hs', '*.lhs' },
            callback = function() vim.lsp.buf.format({ async = false }) end,
          })
        EOF
      '';
    };
  };
}
