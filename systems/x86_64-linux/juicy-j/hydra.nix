{
  pkgs,
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
