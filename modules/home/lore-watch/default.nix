{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.t11s.loreWatch;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  searchType = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Keep this search. Disabled searches are forgotten by lei; their Maildir stays.";
      };
      query = mkOption {
        type = types.str;
        description = "lei/public-inbox query, e.g. `dfn:drivers/soundwire/qcom.c AND d:2026-10-01..`.";
      };
      threads = mkOption {
        type = types.bool;
        default = false;
        description = "Also fetch whole threads of the matches (lei q --threads).";
      };
      ours = mkOption {
        type = types.bool;
        default = false;
        description = "A thread we are in: `lore-new replies` lists replies here.";
      };
      lookback = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "7.days";
        description = ''
          `lei up --remote-fudge-time` for this search every `lookbackEvery`:
          how far before the last successful run that update asks lore again
          (other runs use `quickLookback`). With `threads`, replies only
          arrive if their thread has a match inside this window.
        '';
      };
      description = mkOption {
        type = types.str;
        default = "";
        description = "What the search is for (shown by `lore-new searches`).";
      };
    };
  };

  searches = lib.filterAttrs (_: s: s.enable) cfg.searches;

  configJson = (pkgs.formats.json { }).generate "lore-watch-config.json" {
    inherit (cfg) dir external ownAddresses;
    stateDir = cfg.stateDir;
    notmuchConfig = "${config.xdg.configHome}/lore-watch/notmuch-config";
    inherit (cfg) searchTimeout quickLookback lookbackEvery searchFiles;
    searches = lib.mapAttrs (_: s: {
      inherit (s)
        query
        threads
        ours
        lookback
        description
        ;
    }) searches;
  };
in
{
  options.t11s.loreWatch = {
    enable = mkEnableOption "lore-watch, a local notmuch-indexed copy of the lore.kernel.org mail in t11s.loreWatch.searches";

    package = mkOption {
      type = types.package;
      default = pkgs.t11s.lore-watch;
      defaultText = lib.literalExpression "pkgs.t11s.lore-watch";
      description = "Provides lore-watch-sync and lore-new.";
    };

    dir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/mail/lore";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/mail/lore"'';
      description = "Maildir root: one folder per search, plus notmuch's .notmuch index.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "${config.xdg.stateHome}/lore-watch";
      defaultText = lib.literalExpression ''"''${config.xdg.stateHome}/lore-watch"'';
      description = "lei's private config and saved searches, the run log (runs.jsonl) and the lock.";
    };

    interval = mkOption {
      type = types.str;
      default = "30min";
      example = "1h";
      description = "How often to update (systemd time span, OnUnitActiveSec=).";
    };

    external = mkOption {
      type = types.str;
      default = "https://lore.kernel.org/all/";
      description = "The public-inbox to search.";
    };

    ownAddresses = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Our From: addresses; `lore-new replies` leaves these out.";
    };

    quickLookback = mkOption {
      type = types.nullOr types.str;
      default = "1.day";
      description = ''
        `lei up --remote-fudge-time` on routine runs: each update re-asks lore
        for this much before its last successful query (null: lei's 2 days).
        Searches with their own `lookback` use that every `lookbackEvery`.
      '';
    };

    lookbackEvery = mkOption {
      type = types.ints.positive;
      default = 6 * 3600;
      description = "Seconds between the runs that use each search's own (longer) `lookback`.";
    };

    searchTimeout = mkOption {
      type = types.ints.positive;
      default = 900;
      description = "Seconds before one lei q/up is given up on (retried next run).";
    };

    searchFiles = mkOption {
      type = types.listOf types.str;
      default = [ "${config.xdg.configHome}/lore-watch/searches.json" ];
      defaultText = lib.literalExpression ''[ "''${config.xdg.configHome}/lore-watch/searches.json" ]'';
      description = ''
        JSON files of more searches ({"name": {"query": ..., "threads": ...,
        "ours": ..., "lookback": ..., "description": ...}}), read at run time
        and merged over `searches` (a name in a file wins). For personal
        searches that shouldn't be in this (public) repository. Missing
        files are skipped; a search that disappears is forgotten by lei on
        the next run, its Maildir stays.
      '';
    };

    searches = mkOption {
      type = types.attrsOf searchType;
      default = { };
      example = lib.literalExpression ''
        {
          wcd9378 = {
            query = "dfn:sound/soc/codecs/wcd9378 AND d:2026-10-01..";
            threads = true;
          };
        }
      '';
      description = ''
        Saved searches, name -> lei query. The name is the Maildir folder
        under `dir`. `searches.<name>.enable = false` drops one; searchFiles
        add more at run time.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (n: builtins.match "[A-Za-z0-9][A-Za-z0-9._-]*" n != null) (
          lib.attrNames cfg.searches
        );
        message = "t11s.loreWatch.searches: names must match [A-Za-z0-9][A-Za-z0-9._-]* (they are folder names).";
      }
    ];

    home.packages = [ cfg.package ];

    xdg.configFile."lore-watch/config.json".source = configJson;

    xdg.configFile."lore-watch/notmuch-config".text = ''
      [database]
      path=${cfg.dir}

      [new]
      tags=
      ignore=

      [maildir]
      synchronize_flags=false

      [user]
      primary_email=${lib.head (cfg.ownAddresses ++ [ "" ])}
    '';

    systemd.user.services.lore-watch = {
      Unit = {
        Description = "lore-watch: update saved lore.kernel.org searches and index them";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${cfg.package}/bin/lore-watch-sync --config ${configJson}";
        TimeoutStartSec = "2h";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.lore-watch = {
      Unit.Description = "lore-watch: update lore.kernel.org searches every ${cfg.interval}";
      Timer = {
        OnStartupSec = "5min";
        OnUnitActiveSec = cfg.interval;
        RandomizedDelaySec = "2min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
