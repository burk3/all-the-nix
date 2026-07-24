{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    filterAttrs
    generators
    getExe
    groupBy
    mapAttrs'
    mapAttrsToList
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    ;
  cfg = config.t11s.et-ghostty;

  # GLib allows hyphens in application IDs but recommends against them: the
  # D-Bus object path GApplication derives from the ID permits only
  # [A-Za-z0-9_]. Profile names keep their hyphens; only the class is folded.
  sanitize = builtins.replaceStrings [ "-" ] [ "_" ];

  # One application-ID element: [A-Za-z0-9_-], not starting with a digit.
  # Stricter than GLib for explicit `class` overrides, which would allow an
  # element to start with a hyphen. Profile names are sanitized before this
  # check, so a leading hyphen there becomes an underscore and is accepted.
  elemRe = "[A-Za-z_][A-Za-z0-9_-]*";
  isElem = s: builtins.match elemRe s != null;
  isAppId = s: builtins.match "${elemRe}(\\.${elemRe})+" s != null && builtins.stringLength s <= 255;

  # ghostty's config format is `key = value`, with lists expressed as repeated
  # keys (see font-family in t11s.guiCommon). ghostty parses `key=value` too,
  # but the spacing matches what programs.ghostty generates.
  toGhosttyConf = generators.toKeyValue {
    mkKeyValue = generators.mkKeyValueDefault { } " = ";
    listsAsDuplicateKeys = true;
  };

  profileDir = "${config.xdg.configHome}/ghostty/profiles";
  confPathOf = name: "${profileDir}/${name}.conf";

  # `command` and `class` are applied last so they always match what the
  # assertions validated; `settings` may not define them (asserted below).
  confTextOf =
    profile:
    toGhosttyConf (
      lib.optionalAttrs (profile.tint != null) { background = profile.tint; }
      // profile.settings
      // {
        command = "${cfg.etPackage}/bin/et ${profile.host}";
        inherit (profile) class;
      }
    );

  wrapperOf =
    name:
    pkgs.writeShellScriptBin "et-ghostty-${name}" ''
      exec ${cfg.package}/bin/ghostty --config-file=${confPathOf name} "$@"
    '';

  # Uniqueness is checked on the final class, so it also catches two profiles
  # pinned to the same explicit override.
  classCollisions = filterAttrs (_: entries: builtins.length entries > 1) (
    groupBy (entry: entry.class) (
      mapAttrsToList (name: profile: {
        inherit name;
        inherit (profile) class;
      }) cfg.profiles
    )
  );

  collisionReport = concatStringsSep "; " (
    mapAttrsToList (
      class: entries: "${class} claimed by ${concatStringsSep ", " (map (entry: entry.name) entries)}"
    ) classCollisions
  );

  profileModule =
    { name, ... }:
    {
      options = {
        host = mkOption {
          description = "Target passed verbatim to et. A hostname, user@host, or ssh alias.";
          type = types.str;
          example = "juicy-j";
        };
        tint = mkOption {
          description = ''
            Background colour for this profile's windows, so remote windows are
            visually distinct from local ones. Sugar for `settings.background`,
            which takes precedence if both are set.
          '';
          type = types.nullOr types.str;
          default = null;
          example = "2a1a2e";
        };
        class = mkOption {
          description = ''
            GTK application ID for this profile. A distinct class is what gives
            the profile its own ghostty process rather than merging into the
            local instance, so these must be unique across profiles.
          '';
          type = types.str;
          default = "com.mitchellh.ghostty.${sanitize name}";
          defaultText = "com.mitchellh.ghostty.<profile name, hyphens folded to underscores>";
        };
        settings = mkOption {
          description = ''
            Extra ghostty settings for this profile, same shape as
            `programs.ghostty.settings`. Layered on top of the base ghostty
            config, which still applies. May not set `command` or `class`; use
            `host` and `class` instead.
          '';
          type =
            with types;
            attrsOf (oneOf [
              bool
              int
              str
              (listOf (oneOf [
                bool
                int
                str
              ]))
            ]);
          default = { };
          example = {
            font-size = 9;
          };
        };
        finalPackage = mkOption {
          description = ''
            The generated wrapper that launches this profile. Read-only.
            Reference it wherever a launch command is needed, e.g.

                action.spawn = [
                  (lib.getExe config.t11s.et-ghostty.profiles.juicy-j.finalPackage)
                ];
          '';
          type = types.package;
          readOnly = true;
          default = wrapperOf name;
          defaultText = "the et-ghostty-<name> wrapper script";
        };
      };
    };
in
{
  options.t11s.et-ghostty = {
    enable = mkEnableOption "per-host ghostty profiles that run et instead of a local shell";
    package = mkOption {
      description = "The ghostty package the profile wrappers launch.";
      type = types.package;
      default = config.programs.ghostty.package;
      defaultText = "config.programs.ghostty.package";
    };
    etPackage = mkOption {
      description = ''
        The Eternal Terminal package providing et. Referenced by absolute store
        path, so profiles do not depend on the PATH ghostty inherits from
        whatever spawned it.
      '';
      type = types.package;
      default = pkgs.eternal-terminal;
      defaultText = "pkgs.eternal-terminal";
    };
    desktopEntries.enable = mkEnableOption ''
      a desktop entry per profile, so they show up in application launchers.
      Useful where terminals are launched from a launcher rather than a keybind
    '';
    profiles = mkOption {
      description = ''
        Remote profiles. Each generates a ghostty config setting
        `command = et <host>`, plus an `et-ghostty-<name>` wrapper to launch it.

        Ghostty runs its configured `command` for every surface it creates, so
        every tab and split inside a profile window is a fresh et session to
        that host.
      '';
      type = types.attrsOf (types.submodule profileModule);
      default = { };
      example = {
        juicy-j = {
          host = "devserver";
          tint = "2a1a2e";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Profiles are inert without the et client.
    t11s.eternal-terminal.enable = mkDefault true;

    assertions = [
      {
        assertion = config.programs.ghostty.enable;
        message = "t11s.et-ghostty requires programs.ghostty.enable — profiles are diffs layered on the base ghostty config.";
      }
      {
        assertion = classCollisions == { };
        message = "t11s.et-ghostty: profiles must not share a GTK application class, or launching one will hand off to the other's process and open a window connected to the wrong host. ${collisionReport}";
      }
    ]
    ++ mapAttrsToList (name: _: {
      assertion = isElem (sanitize name);
      message = "t11s.et-ghostty.profiles.${name}: profile name must be usable as a GTK application ID element — only [A-Za-z0-9_-], and must not begin with a digit.";
    }) cfg.profiles
    ++ mapAttrsToList (name: profile: {
      assertion = isAppId profile.class;
      message = "t11s.et-ghostty.profiles.${name}: class '${profile.class}' is not a valid GTK application ID — needs at least two dot-separated elements of [A-Za-z0-9_-], none starting with a digit, at most 255 characters.";
    }) cfg.profiles
    ++ mapAttrsToList (name: profile: {
      assertion = !(profile.settings ? command) && !(profile.settings ? class);
      message = "t11s.et-ghostty.profiles.${name}: settings may not set 'command' or 'class'; use the 'host' and 'class' options so the assertions can validate them.";
    }) cfg.profiles;

    xdg.configFile = mapAttrs' (
      name: profile: nameValuePair "ghostty/profiles/${name}.conf" { text = confTextOf profile; }
    ) cfg.profiles;

    home.packages = mapAttrsToList (_: profile: profile.finalPackage) cfg.profiles;

    # Named after the class so Wayland shells associate the window with the
    # entry: the app_id ghostty reports is the class, and shells match it
    # against the desktop file's basename.
    xdg.desktopEntries = mkIf cfg.desktopEntries.enable (
      mapAttrs' (
        name: profile:
        nameValuePair profile.class {
          name = "Ghostty: ${name}";
          genericName = "Remote terminal";
          comment = "Terminal on ${profile.host} via Eternal Terminal";
          exec = getExe profile.finalPackage;
          # Ghostty's own icon. Profiles are distinguished by tint/theme, not
          # by icon.
          icon = "com.mitchellh.ghostty";
          terminal = false;
          categories = [
            "System"
            "TerminalEmulator"
          ];
          startupNotify = true;
          settings = {
            StartupWMClass = profile.class;
            # ghostty's own entry sets DBusActivatable=true, which works because
            # it ships a matching com.mitchellh.ghostty.service. A profile class
            # has no such service file, so activation would fail — this is the
            # ".desktop files may break" hazard the ghostty `class` docs warn
            # about. Launch via Exec instead.
            DBusActivatable = "false";
          };
        }
      ) cfg.profiles
    );
  };
}
