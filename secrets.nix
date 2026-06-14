let
  burke = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINB1Sw6DgkSfZhsFcNig7dY3IcFbyCYCvIp4gvr9gDeY burke@juicy-j"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFssPVej1nLwAQwHSCUbA3h5Cqz2kj1lSKPmdl+6SIAn burke@freddie-kane"
  ];
  juicy-j = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqCimSANQl9QYxDnkwiAnU+mJGYMdwwMDcpFUJFBatL root@juicy-j";
in
{
  "secrets/mikrotik-exporter.password.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/ha-bearer.token.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/grafana-secret-key.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/pushover-user-key.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/pushover-api-token.age".publicKeys = burke ++ [ juicy-j ];
  "secrets/openclaw-gateway-token.age".publicKeys = burke ++ [ juicy-j ];
}
