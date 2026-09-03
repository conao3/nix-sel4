{
  description = "Nix tooling for building seL4 Microkit systems";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };

      examplesFor = pkgs: {
        hello = import ./examples/hello { inherit pkgs; };
        pingpong = import ./examples/pingpong { inherit pkgs; };
      };

      qemuBoards = nixpkgs.lib.attrNames (
        nixpkgs.lib.filterAttrs (_: b: b ? qemu) (import ./lib/boards.nix)
      );

      # Boots a system under QEMU and asserts that the expected lines appear on
      # the console.
      bootCheck =
        pkgs: name: example: expected:
        pkgs.runCommand "${name}-boots" { } ''
          timeout -s KILL 120 ${example.qemu}/bin/${name}-qemu < /dev/null > console.log 2>&1 || true

          status=0
          ${nixpkgs.lib.concatMapStringsSep "\n" (line: ''
            if ! grep -qF ${nixpkgs.lib.escapeShellArg line} console.log; then
              echo "missing from the QEMU console: ${line}" >&2
              status=1
            fi
          '') expected}

          if [ "$status" -ne 0 ]; then
            cat console.log >&2
            exit 1
          fi

          cp console.log $out
        '';
    in
    {
      overlays.default = final: _prev: {
        microkit-sdk = final.callPackage ./pkgs/microkit-sdk.nix { };
        microkitTools = final.callPackage ./lib { };
      };

      legacyPackages = forAllSystems pkgsFor;

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          examples = examplesFor pkgs;
        in
        {
          inherit (pkgs) microkit-sdk;

          hello-image = examples.hello.image;
          hello-report = examples.hello.report;
          hello-qemu = examples.hello.qemu;

          pingpong-image = examples.pingpong.image;
          pingpong-report = examples.pingpong.report;
          pingpong-qemu = examples.pingpong.qemu;

          default = examples.hello.qemu;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          examples = examplesFor pkgs;
        in
        {
          inherit (pkgs) microkit-sdk;

          pingpong-boots = bootCheck pkgs "pingpong" examples.pingpong [
            "server: waiting for a notification"
            "client: writing into the shared region"
            ''server: received "ping from the client"''
          ];
        }
        // nixpkgs.lib.listToAttrs (
          map (board: {
            name = "hello-boots-${board}";
            value = bootCheck pkgs "hello" (import ./examples/hello { inherit pkgs board; }) [
              "hello, world from nix-sel4"
            ];
          }) qemuBoards
        )
        // {
        }
      );

      # Everything an upstream Microkit tutorial expects: the `microkit` tool,
      # MICROKIT_SDK, the bare-metal cross toolchains and QEMU.
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.microkit-sdk
              pkgs.qemu
              pkgs.gnumake
              pkgs.pkgsCross.aarch64-embedded.stdenv.cc
              pkgs.pkgsCross.riscv64-embedded.stdenv.cc
            ];

            env.MICROKIT_SDK = "${pkgs.microkit-sdk}";
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
