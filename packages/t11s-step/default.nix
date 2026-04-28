{
  stdenv,
  step-cli,
  makeWrapper,
  ...
}:

stdenv.mkDerivation {
  pname = "t11s-step";
  version = "0.1.0";

  src = ./step;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/step $out/bin
    cp -r . $out/step/

    substituteInPlace $out/step/config/defaults.json \
      --replace-fail "/home/burke/.step" "$out/step"

    makeWrapper ${step-cli}/bin/step $out/bin/t11s-step \
      --set STEPPATH $out/step

    runHook postInstall
  '';

  meta.description = "step-cli wrapper preconfigured with the t11s CA bundle";
}
