{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  # Builders dial in to the queue runner over gRPC (services.hydra-builder,
  # via t11s.hydraBuilder) and authenticate with a per-host token. Each one's
  # secrets/hydra-builder-<host>.token.age is listed here so the queue runner
  # accepts it. swaine builds the aarch64-linux jobs (its own closure).
  builders = [
    "juicy-j"
    "swaine"
  ];
  # the wired LAN links, as default.nix configures them; swaine connects over these
  lanInterfaces = lib.mapAttrsToList (_: n: n.matchConfig.Name) config.systemd.network.networks;
  grpcPort = config.services.hydra.queueRunner.grpc.port;

  # Hydra account for Claude Code sessions on this host. Reading needs no
  # login; these roles add starting evaluations and restarting, cancelling
  # and bumping builds. The password is decrypted twice: for hydra-provision,
  # which sets it, and for burke, whose sessions log in with it.
  claudeUser = "claude";
  claudeRoles = [
    "eval-jobset"
    "restart-jobs"
    "cancel-build"
    "bump-to-front"
  ];
  claudePassword = config.age.secrets.hydra-claude-password;

  project = "all-the-nix";
  repo = "https://github.com/burk3/all-the-nix";
  # Jobset name = git branch. Value = how often Hydra polls it, in seconds.
  jobsets = {
    master = 300;
    flake-update = 60;
    prep-2611 = 300;
  };

  projectJson = pkgs.writeText "hydra-project.json" (
    builtins.toJSON {
      name = project;
      displayname = project;
      description = "NixOS hosts from ${repo}";
      homepage = repo;
      enabled = "1";
      visible = "1";
    }
  );
  jobsetJson =
    name: checkinterval:
    pkgs.writeText "hydra-jobset-${name}.json" (
      builtins.toJSON {
        inherit name;
        type = 1; # flake
        flake = "git+${repo}?ref=${name}";
        description = "hydraJobs of the ${name} branch";
        enabled = "1";
        visible = "1";
        checkinterval = toString checkinterval;
        keepnr = "3";
        schedulingshares = "100";
        emailoverride = "";
      }
    );
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
  };

  services.hydra = {
    enable = true;
    listenHost = "127.0.0.1";
    port = 3001;
    hydraURL = "https://hydra.ts.t11s.net";
    notificationSender = "hydra@juicy-j.lan";
    useSubstitutes = true;
    queueRunner = {
      # Plain gRPC: the tokens cross the LAN in the clear, like
      # journal-upload's HTTP from swaine. The firewall below keeps it off
      # the tailnet and the internet.
      grpc.address = "[::]";
      # [::1]:8080 by default, which sits next to ad-hoc servers on 8080
      rest.port = 3002;
      settings.tokenPaths = map (host: config.age.secrets."hydra-builder-${host}-token".path) builders;
    };
    # nixpkgs' Hydra links upstream Nix, but it runs nix-eval-jobs as a
    # separate program. Swapping that for Determinate's build makes Hydra
    # produce the same derivations as `nh os switch` on the other hosts, which
    # is what lets them substitute Hydra's builds.
    package = pkgs.hydra.override {
      nix-eval-jobs = inputs.nix-eval-jobs.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };
    extraConfig = ''
      evaluator_workers = 4
      evaluator_max_memory_size = 8192
      # stylix reads its colour scheme out of a derivation
      allow_import_from_derivation = true
    '';
  };

  # The project and jobsets are declared above, not clicked together in the
  # web UI. This unit re-applies them on every switch through Hydra's REST
  # API, logging in as an admin user whose password is generated for the run
  # and disabled again when the unit exits. It is never stored.
  systemd.services.hydra-provision = {
    description = "Declare the ${project} Hydra project and jobsets";
    wantedBy = [ "multi-user.target" ];
    requires = [ "hydra-server.service" ];
    after = [ "hydra-server.service" ];
    path = [
      config.services.hydra.package
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.libargon2
    ];
    environment = {
      # % doubled: systemd's Environment= would read the URL's %2F as a specifier
      HYDRA_DATABASE_URL = lib.replaceStrings [ "%" ] [ "%%" ] config.services.hydra.dbUrl;
      HYDRA_CONFIG = "/var/lib/hydra/hydra.conf";
      HYDRA_DATA = "/var/lib/hydra";
      PGPASSFILE = "/var/lib/hydra/pgpass";
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "hydra";
      PrivateTmp = true;
    };
    script = ''
      url=http://127.0.0.1:${toString config.services.hydra.port}
      password=$(head -c 24 /dev/urandom | base64)
      # hydra-create-user only takes a plaintext password as an argument, where
      # other local users could see it, so the account is locked again on exit:
      # "!" is the hash Hydra itself gives accounts that cannot log in.
      trap 'hydra-create-user provision --password-hash "!"' EXIT
      hydra-create-user provision --role admin --password "$password"

      cd "$(mktemp -d)"
      api() {
        curl -fsS --referer "$url" \
          -H 'Accept: application/json' -H 'Content-Type: application/json' "$@"
      }
      # printf is a shell builtin, so the password stays out of process arguments
      printf '{"username": "provision", "password": "%s"}' "$password" |
        api --retry 30 --retry-connrefused --retry-delay 2 \
          -X POST -d @- -c cookie "$url/login" >/dev/null
      api -b cookie -X PUT -d @${projectJson} "$url/project/${project}" >/dev/null
      ${lib.concatStrings (
        lib.mapAttrsToList (name: checkinterval: ''
          api -b cookie -X PUT -d @${jobsetJson name checkinterval} "$url/jobset/${project}/${name}" >/dev/null
        '') jobsets
      )}
      # Jobsets that are not declared above are removed, so what Hydra builds
      # is exactly what this file says.
      api "$url/project/${project}" | jq -r '.jobsets[]' | while read -r name; do
        case " ${toString (lib.attrNames jobsets)} " in
          *" $name "*) ;;
          *) api -b cookie -X DELETE "$url/jobset/${project}/$name" >/dev/null ;;
        esac
      done

      # The account Claude Code sessions use: it can start evaluations and
      # restart, cancel or bump builds, but not change projects or jobsets.
      # Its password is hashed here because --password-prompt expects a
      # terminal; the hash only reaches hydra-create-user's arguments.
      hash=$(tr -d '\n' <${claudePassword.path} |
        argon2 "$(head -c 16 /dev/urandom | base64)" -id -t 3 -m 18 -p 1 -e)
      hydra-create-user ${claudeUser} --full-name "Claude Code" --password-hash "$hash" \
        --wipe-roles ${lib.concatMapStringsSep " " (r: "--role ${r}") claudeRoles}
    '';
  };

  services.caddy = {
    enable = true;
    globalConfig = ''
      acme_ca https://turing.lan/acme/acme/directory
    '';
    virtualHosts."hydra.ts.t11s.net, hydra.lan".extraConfig = ''
      tls {
        issuer acme {
          disable_http_challenge
        }
      }
      reverse_proxy 127.0.0.1:3001
    '';
  };

  # The queue runner (hydra-queue-runner:hydra) reads every builder's token;
  # juicy-j's own builder reads its copy through t11s.hydraBuilder.
  age.secrets =
    lib.genAttrs' builders (
      host:
      lib.nameValuePair "hydra-builder-${host}-token" {
        file = ../../../secrets/hydra-builder-${host}.token.age;
        group = "hydra";
        mode = "0440";
      }
    )
    // {
      hydra-claude-password = {
        file = ../../../secrets/hydra-claude.password.age;
        owner = "hydra";
        mode = "0400";
      };
      hydra-claude-password-burke = {
        file = ../../../secrets/hydra-claude.password.age;
        owner = "burke";
        mode = "0400";
      };
    };

  # The local builder takes the x86_64 jobs. i686-linux is listed because
  # Steam on other hosts pulls in 32-bit derivations.
  t11s.hydraBuilder = {
    enable = true;
    queueRunnerAddr = "http://[::1]:${toString grpcPort}";
  };
  services.hydra-builder.settings = {
    systems = [
      "x86_64-linux"
      "i686-linux"
    ];
    maxJobs = 16;
    speedFactor = 1;
    supportedFeatures = [
      "kvm"
      "big-parallel"
      "nixos-test"
      "benchmark"
      "uid-range"
    ];
  };

  networking.firewall.allowedTCPPorts = [ 443 ];
  networking.firewall.interfaces = lib.genAttrs lanInterfaces (_: {
    allowedTCPPorts = [ grpcPort ];
  });
}
