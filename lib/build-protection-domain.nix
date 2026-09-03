{
  boards,
  lib,
  microkit-sdk,
  pkgsCross,
}:

{
  # Name of the protection domain. The resulting ELF is installed as
  # `$out/<name>.elf`, which is the file name `program_image` must refer to.
  name,
  board,
  config ? "debug",
  src,
  sdk ? microkit-sdk,
  # Source files relative to `src`. Defaults to every .c / .s / .S under `src`.
  sources ? null,
  extraCFlags ? [ ],
  extraLDFlags ? [ ],
  extraLibs ? [ ],
  nativeBuildInputs ? [ ],
  meta ? { },
}:

let
  boardInfo =
    boards.${board}
      or (throw "nix-sel4: 未知の board '${board}' です。boards.nix にある ${toString (lib.length (lib.attrNames boards))} 個のいずれかを指定してください");

  _ =
    lib.throwIf (!lib.elem config boardInfo.configs)
      "nix-sel4: board '${board}' は config '${config}' を持ちません (利用できるのは ${lib.concatStringsSep ", " boardInfo.configs})";

  crossPkgs =
    {
      aarch64 = pkgsCross.aarch64-embedded;
      riscv64 = pkgsCross.riscv64-embedded;
    }
    .${boardInfo.arch} or (throw "nix-sel4: arch '${boardInfo.arch}' 向けのクロスツールチェーンは未対応です");

  archCFlags =
    {
      aarch64 = [ "-mstrict-align" ];
      riscv64 = [
        "-march=rv64imafdc_zicsr_zifencei"
        "-mabi=lp64d"
      ];
    }
    .${boardInfo.arch};

  boardDir = "${sdk}/board/${board}/${config}";

  programImage = "${name}.elf";

  ld = "${crossPkgs.stdenv.cc.targetPrefix}ld";

  cflags = [
    "-nostdlib"
    "-ffreestanding"
    "-g"
    "-O3"
    "-Wall"
    "-Wno-unused-function"
    "-Werror"
    "-I${boardDir}/include"
    "-I."
  ]
  ++ archCFlags
  ++ extraCFlags;

  ldflags = [ "-L${boardDir}/lib" ] ++ extraLDFlags;

  libs = [
    "-lmicrokit"
    "-Tmicrokit.ld"
  ]
  ++ extraLibs;
in
lib.seq _ (
  crossPkgs.stdenv.mkDerivation {
    pname = name;
    inherit (sdk) version;
    inherit src nativeBuildInputs;

    strictDeps = true;
    hardeningDisable = [ "all" ];
    dontStrip = true;

    buildPhase = ''
      runHook preBuild

      ${lib.optionalString (sources != null) ''
        srcFiles=(${lib.escapeShellArgs sources})
      ''}
      ${lib.optionalString (sources == null) ''
        mapfile -t srcFiles < <(find . -type f \( -name '*.c' -o -name '*.s' -o -name '*.S' \) -printf '%P\n' | sort)
      ''}

      if [ ''${#srcFiles[@]} -eq 0 ]; then
        echo "nix-sel4: ${name} にコンパイル対象のソースがありません" >&2
        exit 1
      fi

      objs=()
      for s in "''${srcFiles[@]}"; do
        obj="$(printf '%s' "''${s%.*}" | tr '/' '_').o"
        echo "CC $s -> $obj"
        $CC -c ${lib.escapeShellArgs cflags} "$s" -o "$obj"
        objs+=("$obj")
      done

      echo "LD ${programImage}"
      ${ld} ${lib.escapeShellArgs ldflags} "''${objs[@]}" ${lib.escapeShellArgs libs} -o "${programImage}"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -Dm644 ${programImage} $out/${programImage}

      runHook postInstall
    '';

    passthru = {
      inherit programImage board config;
      inherit (boardInfo) arch;
    };

    meta = {
      description = "seL4 Microkit protection domain '${name}' for ${board}";
    }
    // meta;
  }
)
