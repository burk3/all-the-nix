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
    nixfmt
    nixfmt-tree
    statix
    # vulnix
    haskellPackages.dhall-nix
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
