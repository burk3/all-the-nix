{ fetchzip, stdenv, ... }:
stdenv.mkDerivation {
  pname = "starship-win";
  version = "1.23.0";

  src = fetchzip {
    url = "https://github.com/starship/starship/releases/download/v1.23.0/starship-x86_64-pc-windows-msvc.zip";
    hash = "sha256-a9ifichyVdAY2X3rVurefs9z5gThxNMM76onej02RCo=";
  };

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp starship.exe $out/bin/
    chmod a+x $out/bin/starship.exe

    runHook postInstall
  '';

  meta = {
    description = "windows binary for starship packaged for wsl integration";
  };
}
