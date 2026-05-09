{ config, ... }:
{
  ### node-exporter — local-only
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9100;
    # default enabled collectors are fine
  };

  ### agenix-managed secret for mikrotik-exporter
  age.secrets."mikrotik-exporter.env" = {
    file = ../../../secrets/mikrotik-exporter.env.age;
    owner = "mikrotik-exporter";
    group = "mikrotik-exporter";
    mode = "0400";
  };

  # The exporter framework defaults to DynamicUser=true. Dynamic users don't
  # exist in /etc/passwd outside of an active unit, so agenix's activation-
  # time chown of the secret to `mikrotik-exporter` fails on the first
  # rebuild. Pre-declare a static user/group and force DynamicUser=false so
  # systemd uses our static user (which is in /etc/passwd before activation).
  users.users.mikrotik-exporter = {
    isSystemUser = true;
    group = "mikrotik-exporter";
  };
  users.groups.mikrotik-exporter = { };

  ### mikrotik-exporter — reads MIKROTIK_USER / MIKROTIK_PASSWORD from EnvironmentFile
  services.prometheus.exporters.mikrotik = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9436;
    configuration = {
      devices = [
        {
          name = "molly";
          address = "10.1.1.1";
        }
        {
          name = "case";
          address = "10.1.1.3";
        }
        {
          name = "wintermute";
          address = "10.1.1.5";
        }
      ];
      features = {
        health = true;
        monitor = true;
        firmware = true;
        optics = true;
      };
    };
  };

  systemd.services.prometheus-mikrotik-exporter.serviceConfig = {
    DynamicUser = false;
    EnvironmentFile = config.age.secrets."mikrotik-exporter.env".path;
  };

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
