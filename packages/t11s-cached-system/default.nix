{
  writeShellApplication,
  git,
  curl,
  jq,
  ...
}:
writeShellApplication {
  name = "t11s-cached-system";
  runtimeInputs = [
    git
    curl
    jq
  ];
  text = builtins.readFile ./t11s-cached-system.sh;
  meta.description = "print the system closure Hydra built for the checked-out commit";
}
