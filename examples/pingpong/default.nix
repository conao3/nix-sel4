{
  pkgs,
  board ? "qemu_virt_aarch64",
  config ? "debug",
}:

let
  inherit (pkgs) microkitTools;

  sharedVaddr = 33554432; # 0x2000000

  client = microkitTools.buildProtectionDomain {
    name = "client";
    inherit board config;
    src = ./client;
  };

  server = microkitTools.buildProtectionDomain {
    name = "server";
    inherit board config;
    src = ./server;
  };
in
microkitTools.buildSystem {
  name = "pingpong";
  inherit board config;

  system = microkitTools.mkSystemDescription {
    memoryRegions.shared = {
      size = 4096;
    };

    protectionDomains = {
      server = {
        priority = 200;
        programImage = server.programImage;
        maps = [
          {
            mr = "shared";
            vaddr = sharedVaddr;
            perms = "rw";
            setvarVaddr = "shared_vaddr";
          }
        ];
      };

      client = {
        priority = 100;
        programImage = client.programImage;
        maps = [
          {
            mr = "shared";
            vaddr = sharedVaddr;
            perms = "rw";
            setvarVaddr = "shared_vaddr";
          }
        ];
      };
    };

    channels = [
      {
        ends = [
          {
            pd = "server";
            setvarId = "client_channel";
          }
          {
            pd = "client";
            setvarId = "server_channel";
          }
        ];
      }
    ];
  };

  pds = {
    ${client.programImage} = client;
    ${server.programImage} = server;
  };
}
