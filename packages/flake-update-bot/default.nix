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
  ...
}:
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
  ];
  # SC2016: the script prints markdown, so backticks inside single-quoted
  # printf formats are literal, not forgotten expansions.
  excludeShellChecks = [ "SC2016" ];
  text = builtins.readFile ./flake-update-bot.sh;
  meta.description = "weekly flake.lock update PR, gated on Hydra, with a Claude Code fix loop";
}
