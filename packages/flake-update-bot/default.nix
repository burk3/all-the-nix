{
  pkgs,
  inputs,
  writeShellApplication,
  git,
  gh,
  curl,
  jq,
  util-linux,
  coreutils,
  gnugrep,
  bubblewrap,
  socat,
  ...
}:
let
  # The one command Claude may run outside its sandbox. See fub.sh.
  fub = writeShellApplication {
    name = "fub";
    # nix is deliberately absent here too: it comes from the service's PATH.
    runtimeInputs = [
      git
      jq
      coreutils
      gnugrep
    ];
    text = builtins.readFile ./fub.sh;
  };
in
writeShellApplication {
  name = "flake-update-bot";
  # nix is deliberately absent: the service puts the system's Determinate Nix
  # on PATH, and the bot must evaluate with the same Nix the hosts use.
  runtimeInputs = [
    git
    gh
    curl
    jq
    util-linux
    coreutils
    gnugrep
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
    fub
    # Claude Code's sandbox on Linux
    bubblewrap
    socat
  ];
  # SC2016: the script prints markdown, so backticks inside single-quoted
  # printf formats are literal, not forgotten expansions.
  excludeShellChecks = [ "SC2016" ];
  text = ''
    FUB_CLAUDE_SETTINGS=${./claude-settings.json}
    FUB_CLAUDE_INSTRUCTIONS=${./claude-instructions.md}
  ''
  + builtins.readFile ./flake-update-bot.sh;
  passthru = { inherit fub; };
  meta.description = "weekly flake.lock update PR, gated on Hydra, with a Claude Code fix loop";
}
