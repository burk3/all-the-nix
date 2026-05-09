_: final: prev: {
  # Bump this assertion alongside ./env-fallback.patch when nixpkgs moves the
  # exporter to a newer upstream — the patch's hunk context lives in main.go's
  # loadConfigFromFile, which has been stable for years but isn't promised to be.
  prometheus-mikrotik-exporter =
    assert prev.prometheus-mikrotik-exporter.version == "2021-08-10";
    prev.prometheus-mikrotik-exporter.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./env-fallback.patch ];
    });
}
