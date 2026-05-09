{ config, ... }:
let
  # Hardcoded because the exporter doesn't expand env vars or systemd
  # specifiers inside its YAML config. The unit name is stable.
  passwordFile = "/run/credentials/prometheus-mikrotik-exporter.service/mikrotik-exporter.password";
in
{
  ### node-exporter — local-only
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9100;
  };

  ### agenix-managed password for mikrotik-exporter
  # systemd LoadCredential below reads this as root and republishes it into
  # the unit's credentials dir, so no owner/group/mode tweaks are needed.
  age.secrets."mikrotik-exporter.password".file = ../../../secrets/mikrotik-exporter.password.age;

  ### mikrotik-exporter — per-device password_file via burk3 fork
  services.prometheus.exporters.mikrotik = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9436;
    configuration = {
      devices = [
        {
          name = "molly";
          address = "10.1.1.1";
          user = "exporter";
          password_file = passwordFile;
        }
        {
          name = "case";
          address = "10.1.1.3";
          user = "exporter";
          password_file = passwordFile;
        }
        {
          name = "wintermute";
          address = "10.1.1.5";
          user = "exporter";
          password_file = passwordFile;
          features = {
            dhcpl = true;
            container = true;
          };
        }
      ];
      features = {
        health = true;
        monitor = true;
        firmware = true;
        optics = true;
        ethernet = true;
      };
    };
  };

  systemd.services.prometheus-mikrotik-exporter.serviceConfig.LoadCredential =
    "mikrotik-exporter.password:${config.age.secrets."mikrotik-exporter.password".path}";

  ### VictoriaMetrics — local-only TSDB
  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:8428";
    retentionPeriod = "3"; # no suffix => months
    prometheusConfig = {
      scrape_configs = [
        {
          job_name = "node";
          scrape_interval = "15s";
          static_configs = [ { targets = [ "127.0.0.1:9100" ]; } ];
        }
        {
          job_name = "mikrotik";
          scrape_interval = "30s";
          static_configs = [ { targets = [ "127.0.0.1:9436" ]; } ];
        }
      ];
    };
  };

  ### Grafana — bound 0.0.0.0:3000, firewalled to tailscale only
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
        domain = "juicy-j.dab-ling.ts.net";
        root_url = "http://juicy-j.dab-ling.ts.net:3000/";
      };
      "auth.anonymous" = {
        enabled = true;
        org_role = "Admin";
      };
      auth = {
        disable_login_form = true;
      };
      analytics.reporting_enabled = false;
    };
    provision.datasources.settings.datasources = [
      {
        name = "VictoriaMetrics";
        type = "prometheus";
        access = "proxy";
        url = "http://127.0.0.1:8428";
        isDefault = true;
      }
    ];
  };

  ### Firewall — open Grafana only on the tailscale interface
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3000 ];
}
