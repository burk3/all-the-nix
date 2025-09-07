{ fetchzip, stdenv, ... }:

stdenv.mkDerivation {
  pname = "npiperelay-win";
  version = "0.1.0";

  src = fetchzip {
    url = "https://github.com/jstarks/npiperelay/releases/download/v0.1.0/npiperelay_windows_amd64.zip";
    stripRoot = false;
    hash = "sha256-GcwreB8BXYGNKJihE2xeelsroy+JFqLK1NK7Ycqxw5g=";
  };
  
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp npiperelay.exe $out/bin/

    runHook postInstall
  '';

  meta = {
    description = "npiperelay is a tool that allows you to access a Windows named pipe in a way that is more compatible with a variety of command-line tools. With it, you can use Windows named pipes from the Windows Subsystem for Linux (WSL).";
  };
}
