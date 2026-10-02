{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  # Hydra reads only this file. Keeping the localhost builder out of
  # nix.buildMachines means /etc/nix/machines is never written, so interactive
  # `nix build` does not try to SSH into this machine. i686-linux is listed
  # because Steam on other hosts pulls in 32-bit derivations.
  machines = pkgs.writeText "hydra-machines" ''
    localhost x86_64-linux,i686-linux - 16 1 kvm,big-parallel,nixos-test,benchmark - -
  '';

  project = "all-the-nix";
  repo = "https://github.com/burk3/all-the-nix";
  # Jobset name = git branch. Value = how often Hydra polls it, in seconds.
  jobsets = {
    master = 300;
    flake-update = 60;
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
    buildMachinesFiles = [ "${machines}" ];
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
    ];
    environment = {
      HYDRA_DBI = config.services.hydra.dbi;
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

  networking.firewall.allowedTCPPorts = [ 443 ];
}
