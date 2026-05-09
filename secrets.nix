let
  burke = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINB1Sw6DgkSfZhsFcNig7dY3IcFbyCYCvIp4gvr9gDeY burke@juicy-j"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFssPVej1nLwAQwHSCUbA3h5Cqz2kj1lSKPmdl+6SIAn burke@freddie-kane"
  ];
  juicy-j = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOqCimSANQl9QYxDnkwiAnU+mJGYMdwwMDcpFUJFBatL root@juicy-j";
in
{
  "secrets/mikrotik-exporter.env.age".publicKeys = burke ++ [ juicy-j ];
}
