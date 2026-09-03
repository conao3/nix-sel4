# nix-sel4

Nix tooling for building [seL4 Microkit](https://docs.sel4.systems/projects/microkit/) systems. It packages the Microkit SDK, cross-compiles protection domains, renders the system description, runs the `microkit` tool and hands back a QEMU runner, so a booting seL4 system is one command away:

```sh
nix run github:conao3/nix-sel4
```

```
LDR|INFO: loader for seL4 starting
...
Booting all finished, dropped to user space
MON|INFO: Microkit Monitor started!
hello, world from nix-sel4
```

Quit QEMU with `Ctrl-A` then `x`.

## Why

Getting a first Microkit system to boot normally means downloading the SDK tarball by hand, pointing `MICROKIT_SDK` at it, installing an `aarch64-none-elf` toolchain, writing a Makefile that stitches together the per-board `libmicrokit.a` and linker script, writing the system description XML, and finding the right `qemu-system-aarch64` incantation for your board. This flake does all of that.

## What it provides

The overlay adds two attributes to your package set:

| attr | content |
|---|---|
| `microkit-sdk` | The official SDK (currently 2.3.0), installed verbatim. `bin/microkit` is statically linked, so nothing is patched |
| `microkitTools` | `buildProtectionDomain`, `buildSystem`, `mkSystemDescription`, plus the `boards` and `qemuBoards` tables |

### `microkitTools.buildProtectionDomain`

Cross-compiles one protection domain against the SDK for a given board and configuration.

```nix
microkitTools.buildProtectionDomain {
  name = "hello";                  # produces $out/hello.elf
  board = "qemu_virt_aarch64";
  config = "debug";                # debug | release | benchmark | smp-*
  src = ./hello;                   # every .c / .s / .S below it is compiled
}
```

Optional arguments: `sources` (explicit file list relative to `src`), `extraCFlags`, `extraLDFlags`, `extraLibs`, `nativeBuildInputs`, `sdk`, `meta`.

The toolchain is picked from the board's architecture: `pkgsCross.aarch64-embedded` for AArch64 boards and `pkgsCross.riscv64-embedded` for RISC-V ones. The compiler and linker flags match the ones the SDK's own examples use.

The result carries `passthru.programImage` (`"hello.elf"`), which is what the system description's `program_image` must refer to.

### `microkitTools.buildSystem`

Runs the `microkit` tool over a system description and a set of protection domain images.

```nix
microkitTools.buildSystem {
  name = "hello";
  board = "qemu_virt_aarch64";
  config = "debug";
  system = ./hello.system;         # a path, or the XML text itself
  pds."hello.elf" = helloPd;       # program_image name -> derivation
}
```

Returns an attribute set:

| attr | content |
|---|---|
| `image` | Derivation holding `loader.img` |
| `report` | Derivation holding the resource allocation `report.txt` |
| `qemu` | App derivation that boots `image` under QEMU, for boards that support it |
| `sdk` | The SDK used for this build |
| `searchPath` | The `--search-path` tree handed to the `microkit` tool |

The `program_image` entries in the system description are matched against the keys of `pds` during evaluation, so a typo in either fails before anything is compiled.

### `microkitTools.mkSystemDescription`

Renders the system description XML from an attribute set. Addresses and sizes are plain Nix integers.

```nix
microkitTools.mkSystemDescription {
  memoryRegions.shared = { size = 4096; };

  protectionDomains = {
    server = {
      priority = 200;
      programImage = "server.elf";
      maps = [ { mr = "shared"; vaddr = 33554432; perms = "rw"; setvarVaddr = "shared_vaddr"; } ];
    };
    client = {
      priority = 100;
      programImage = "client.elf";
      maps = [ { mr = "shared"; vaddr = 33554432; perms = "rw"; setvarVaddr = "shared_vaddr"; } ];
    };
  };

  channels = [
    {
      ends = [
        { pd = "server"; setvarId = "client_channel"; }
        { pd = "client"; setvarId = "server_channel"; }
      ];
    }
  ];
}
```

Writing the description in Nix buys you evaluation-time checks that the XML alone cannot give:

- channel and IRQ identifiers are allocated per protection domain, out of the same identifier space the kernel uses, and refuse to exceed 62
- `map` entries that name a memory region which does not exist are rejected
- two mappings that overlap inside one protection domain are rejected, with both regions named
- every `channel` end must name a declared protection domain

Anything the generator does not cover can still be written by hand: `buildSystem` accepts a `.system` file directly.

## Supported boards

Every board the SDK ships, 28 of them, is described in [`lib/boards.nix`](lib/boards.nix) with its architecture and the configurations it offers. Three of them boot under the `qemu` runner: `qemu_virt_aarch64`, `qemu_virt_aarch64_el1` and `qemu_virt_riscv64`. For the rest, build `image` and flash it the way the board's manual describes.

Protection domains can be cross-compiled for the AArch64 and RISC-V boards. The two x86-64 boards are described but their toolchain is not wired up yet.

## Development shell

```sh
nix develop github:conao3/nix-sel4
```

The shell exports `MICROKIT_SDK` and puts `microkit`, `aarch64-none-elf-*`, `riscv64-none-elf-*`, `make` and QEMU on `PATH`. The examples shipped inside the SDK build there unmodified:

```sh
cp -r "$MICROKIT_SDK/example/hello" . && chmod -R u+w hello && cd hello
mkdir -p build
make BUILD_DIR=build MICROKIT_BOARD=qemu_virt_aarch64 MICROKIT_CONFIG=debug MICROKIT_SDK="$MICROKIT_SDK"
```

## Examples

- [`examples/hello`](examples/hello) — one protection domain that prints on the debug console.
- [`examples/pingpong`](examples/pingpong) — two protection domains sharing a memory region and a channel. The channel identifier and the shared mapping address reach the C code through `setvar_id` and `setvar_vaddr`, so neither is hardcoded.

Both are wired into `nix flake check`, which boots them under QEMU and asserts the expected console output. `hello` is booted on all three QEMU boards, so the AArch64, AArch64-at-EL1 and RISC-V paths are all covered.

```sh
nix run github:conao3/nix-sel4#hello-qemu
nix run github:conao3/nix-sel4#pingpong-qemu
nix build github:conao3/nix-sel4#hello-report && cat result/report.txt
```

[nix-sel4-example](https://github.com/conao3/nix-sel4-example) is a standalone repository you can clone as a starting point for your own system.

## Usage

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-sel4.url = "github:conao3/nix-sel4";
    nix-sel4.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, nix-sel4, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ nix-sel4.overlays.default ];
      };

      board = "qemu_virt_aarch64";
      config = "debug";

      hello = pkgs.microkitTools.buildProtectionDomain {
        name = "hello";
        inherit board config;
        src = ./hello;
      };

      sys = pkgs.microkitTools.buildSystem {
        name = "hello";
        inherit board config;
        system = pkgs.microkitTools.mkSystemDescription {
          protectionDomains.hello.programImage = hello.programImage;
        };
        pds.${hello.programImage} = hello;
      };
    in
    {
      packages.${system} = {
        inherit (sys) image report;
        default = sys.qemu;
      };
    };
}
```

## Requirements

`x86_64-linux` or `aarch64-linux`. QEMU emulates the target architecture, so no KVM and no seL4 hardware is needed to run the examples.

## Related

- [seL4/microkit](https://github.com/seL4/microkit) — the framework and the SDK this builds on
- [seL4/rust-sel4](https://github.com/seL4/rust-sel4) — Rust bindings, including a `sel4-microkit` crate
- [LionsOS](https://lionsos.org/) — a modular OS built out of Microkit components
- [nix-msb](https://github.com/conao3/nix-msb) — the same idea for microsandbox microVMs

## License

Apache-2.0. The Microkit SDK it downloads is BSD-2-Clause; the seL4 kernel inside it is GPLv2.
