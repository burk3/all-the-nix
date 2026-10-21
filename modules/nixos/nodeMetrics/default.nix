# node-exporter for juicy-j's VictoriaMetrics to scrape over the tailnet.
{
  config,
  lib,
  ...
}:
let
  cfg = config.t11s.nodeMetrics;
in
with lib;
{
  options.t11s.nodeMetrics = {
    enable = mkEnableOption "node-exporter, scrapeable over tailscale";
    port = mkOption {
      type = types.port;
      default = 9100;
    };
  };

  config = mkIf cfg.enable {
    services.prometheus.exporters.node = {
      enable = true;
      inherit (cfg) port;
      enabledCollectors = [ "systemd" ];
    };
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];
  };
}
