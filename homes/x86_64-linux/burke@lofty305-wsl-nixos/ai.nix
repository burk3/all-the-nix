{ pkgs, ... }:
{
  home.sessionVariables = {
    OLLAMA_API_BASE = "http://172.31.224.1:11434";
  };
  #home.sessionPath = [
  #  "/home/burke/.claude/local/"
  #];
}
