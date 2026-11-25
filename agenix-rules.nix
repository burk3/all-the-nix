let
  burke = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINB1Sw6DgkSfZhsFcNig7dY3IcFbyCYCvIp4gvr9gDeY burke@juicy-j"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFssPVej1nLwAQwHSCUbA3h5Cqz2kj1lSKPmdl+6SIAn burke@freddie-kane"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICArqGPqspAdGZswjWOtfHjJ+BWtWjR234InGSzrzaRR burke@freddie-kane"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIMg3iSlBWmImrX9QBcs4KlaXK+79DmuLp0v1GLKVCah burke@zenbook-a16"
  ];
  juicy-j = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqCimSANQl9QYxDnkwiAnU+mJGYMdwwMDcpFUJFBatL root@juicy-j";
  freddie-kane = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPQ3ecd8+ZGsPbqWTUqmGywcXWdCIaG2ZuYU2zqtRom7 root@freddie-kane";
  swaine = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOJuWH2H38kO9Wo0Jzxfq+cSp42309OtqnNxHIXYzvyA root@swaine";
in
{
  "secrets/mikrotik-exporter.password.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/ha-bearer.token.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/grafana-secret-key.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/pushover-user-key.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/pushover-api-token.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/openclaw-gateway-token.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/flake-update-bot-gh-token.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/claude-oauth-token.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/upsmon.password.age".publicKeys = burke ++ [ juicy-j ];
  # hydra-builder tokens: each builder holds its own; juicy-j's queue runner checks all
  "secrets/hydra-builder-juicy-j.token.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/hydra-builder-swaine.token.age".publicKeys = burke ++ [
    juicy-j
    swaine
  ];
  # Hydra login for Claude Code sessions on juicy-j (see systems/x86_64-linux/juicy-j/hydra.nix)
  "secrets/hydra-claude.password.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/private-nix.conf.age".publicKeys = burke;
  "secrets/nixbuild-dot-net.ssh-key.age".publicKeys = burke ++ [
    freddie-kane
    juicy-j
  ];
}
