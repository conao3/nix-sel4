{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "2.3.0";

  sources = {
    "x86_64-linux" = {
      url = "https://github.com/seL4/microkit/releases/download/${version}/microkit-sdk-${version}-linux-x86-64.tar.gz";
      hash = "sha256-4S5Qf3LIfL9cUU356bDGYQO0IpiFL0TARdVynqPeT4k=";
    };
    "aarch64-linux" = {
      url = "https://github.com/seL4/microkit/releases/download/${version}/microkit-sdk-${version}-linux-aarch64.tar.gz";
      hash = "sha256-mKGL1dkDhsenKlQQg6jhoxKa6DvyfXHGV1mzY0RxiEE=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "microkit-sdk: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "microkit-sdk";
  inherit version;

  src = fetchurl {
    inherit (source) url hash;
  };

  __structuredAttrs = true;
  strictDeps = true;

  # bin/microkit is a static-pie executable and the board ELF files carry the
  # symbols the microkit tool reads, so the whole tree is installed verbatim.
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r . $out/
    chmod +x $out/bin/microkit

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/microkit --help > /dev/null

    runHook postInstallCheck
  '';

  meta = {
    description = "SDK for the seL4 Microkit operating system framework";
    homepage = "https://docs.sel4.systems/projects/microkit/";
    changelog = "https://github.com/seL4/microkit/releases/tag/${finalAttrs.version}";
    license = lib.licenses.bsd2;
    mainProgram = "microkit";
    platforms = lib.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
