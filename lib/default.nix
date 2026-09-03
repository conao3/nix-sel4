{
  callPackage,
  lib,
}:

let
  boards = import ./boards.nix;
in
{
  inherit boards;

  buildProtectionDomain = callPackage ./build-protection-domain.nix { inherit boards; };
  buildSystem = callPackage ./build-system.nix { inherit boards; };
  mkSystemDescription = import ./system-description.nix { inherit lib; };

  # Boards that can be booted with the `qemu` runner returned by buildSystem.
  qemuBoards = lib.filterAttrs (_: b: b ? qemu) boards;
}
