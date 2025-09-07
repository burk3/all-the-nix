{ fetchzip, stdenv, ... }:
stdenv.mkDerivation {
  pname = "starship-win";
  version = "1.23.0";

  src = fetchzip {
    url = "https://github.com/starship/starship/releases/download/v1.23.0/starship-aarch64-pc-windows-msvc.zip";
    hash = "sha256-J/2TiEQsaOjFoehpQk1I4bSGJmYlBwovsfpVrUOmvww=";
  };

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp starship.exe $out/bin/

    runHook postInstall
  '';

  meta = {
    description = "windows binary for starship packaged for wsl integration";
  };
}
