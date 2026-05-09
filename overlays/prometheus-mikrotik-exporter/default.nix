inputs: final: _prev:
{
  prometheus-mikrotik-exporter =
    inputs.mikrotik-exporter.packages.${final.stdenv.hostPlatform.system}.default;
}
