{
  pkgs,
  mkShell,
  inputs,
  ...
}:
mkShell {
  packages = with pkgs; [
    cachix
    lorri
    niv
    nil
    nixfmt-rfc-style
    nixfmt-tree
    statix
    # vulnix
    haskellPackages.dhall-nix
    inputs.agenix.packages.${pkgs.system}.default
  ];
}
