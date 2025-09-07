{
  pkgs,
  mkShell,
  ...
}:
mkShell {
  packages = with pkgs; [
    cachix
    lorri
    niv
    nixfmt-rfc-style
    nixfmt-tree
    statix
    # vulnix
    haskellPackages.dhall-nix
  ];
}
