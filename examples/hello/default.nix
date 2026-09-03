{
  pkgs,
  board ? "qemu_virt_aarch64",
  config ? "debug",
}:

let
  inherit (pkgs) microkitTools;

  hello = microkitTools.buildProtectionDomain {
    name = "hello";
    inherit board config;
    src = ./src;
  };
in
microkitTools.buildSystem {
  name = "hello";
  inherit board config;

  system = microkitTools.mkSystemDescription {
    protectionDomains.hello = {
      programImage = hello.programImage;
    };
  };

  pds.${hello.programImage} = hello;
}
