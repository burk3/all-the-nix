{
  lib,
  python3Packages,
  makeWrapper,
  public-inbox,
  notmuch,
  curl,
  git,
}:

# lore-watch, standard-library Python:
#   lore-watch-sync   run by the lore-watch user timer (modules/home/lore-watch.nix):
#                     creates/updates the saved lei searches, `lei up`, `notmuch new`
#   lore-new          reads new mail from the notmuch index (list, replies, show,
#                     status, searches)
# The unit tests run lore-watch-sync against a fake lei and the real notmuch,
# then lore-new on the result.
python3Packages.buildPythonApplication {
  pname = "lore-watch";
  version = "0.1.0";
  pyproject = true;
  src = ./.;

  build-system = [ python3Packages.setuptools ];
  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    notmuch
  ];

  # lei runs curl (and git) by name for remote externals.
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      public-inbox
      notmuch
      curl
      git
    ])
  ];

  meta = {
    description = "A local, notmuch-indexed copy of the lore.kernel.org mail the A16 bring-up follows";
    mainProgram = "lore-new";
    platforms = lib.platforms.linux;
  };
}
