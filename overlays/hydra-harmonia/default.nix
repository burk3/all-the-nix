# TEMPORARY, until nixpkgs' hydra includes NixOS/hydra#2062.
#
# Hydra's Rust daemons talk to the local nix-daemon through harmonia-protocol,
# whose ActivityType rejected discriminants it does not know. Determinate Nix
# sends one, so every build step on our builders failed with "No discriminant
# in enum `ActivityType` matches the value `10113`". nix-community/harmonia
# e8437187b and d7d1feaee tolerate unknown ones. The patch moves every harmonia
# crate in Hydra's Cargo.lock to 8d717e0, which has both, the same bump #2062
# makes (`cargo update -p harmonia-protocol --precise 8d717e0`).
#
# Pinned to the Hydra rev the patch was made against: when nixpkgs moves Hydra,
# evaluation stops here. Drop this overlay if the new rev has the fix,
# otherwise regenerate the patch and cargoHash against it.
_inputs: final: prev:
let
  inherit (prev) lib;
  hydraRev = "c7eee7d7635df188c4e6640b38036ce127457109";
  src = final.applyPatches {
    name = "hydra-src-harmonia-8d717e0";
    inherit (prev.hydra) src;
    patches = [ ./harmonia-8d717e0.patch ];
  };
  # every package built from Hydra's Cargo workspace; they share one vendor hash
  workspace = [
    "hydra-ad-hoc"
    "hydra-builder"
    "hydra-evaluator"
    "hydra-queue-runner"
    "hydra-ws"
  ];
in
# The check sits inside each value: the attribute names must not depend on prev.
lib.genAttrs workspace (
  name:
  assert lib.assertMsg (prev.hydra.src.rev == hydraRev)
    "overlays/hydra-harmonia: nixpkgs' hydra moved off ${hydraRev}; drop the overlay if it has NixOS/hydra#2062, else regenerate the patch";
  prev.${name}.overrideAttrs {
    inherit src;
    cargoHash = "sha256-/AIqHJ41ry17Du1W+o+WJKo+egZqiAnuwdi3ithYI4U=";
  }
)
