{
  pkgs,
  ...
}:
{
  services.rke2 = {
    enable = true;
    role = "agent";
    tokenFile = "/root/rke2-token";
    serverAddr = "https://bronson.dab-ling.ts.net:9345";
    nodeIP = "100.95.232.83";
  };
}
