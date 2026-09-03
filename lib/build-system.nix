{
  boards,
  lib,
  microkit-sdk,
  qemu,
  runCommand,
  writeShellApplication,
}:

{
  name,
  board,
  config ? "debug",
  # Path to a .system file, or the XML text itself (as produced by
  # mkSystemDescription).
  system,
  # program_image file name -> derivation providing it.
  pds ? { },
  sdk ? microkit-sdk,
  extraFlags ? [ ],
}:

let
  boardInfo =
    boards.${board}
      or (throw "nix-sel4: 未知の board '${board}' です。boards.nix にある ${toString (lib.length (lib.attrNames boards))} 個のいずれかを指定してください");

  configOk =
    lib.throwIf (!lib.elem config boardInfo.configs)
      "nix-sel4: board '${board}' は config '${config}' を持ちません (利用できるのは ${lib.concatStringsSep ", " boardInfo.configs})";

  systemFile = if lib.isString system then builtins.toFile "${name}.system" system else system;

  xml = if lib.isString system then system else builtins.readFile system;

  declaredImages = lib.unique (
    map (m: lib.elemAt m 0) (
      lib.filter lib.isList (builtins.split ''<program_image[^>]*path="([^"]+)"'' xml)
    )
  );

  providedImages = lib.attrNames pds;

  missing = lib.subtractLists providedImages declaredImages;
  unused = lib.subtractLists declaredImages providedImages;

  imagesOk =
    lib.throwIf (missing != [ ])
      "nix-sel4: system description の program_image ${lib.concatStringsSep ", " missing} に対応する derivation が pds にありません"
      (
        lib.throwIf (unused != [ ])
          "nix-sel4: pds の ${lib.concatStringsSep ", " unused} は system description の program_image から参照されていません"
      );

  searchPath = runCommand "${name}-search-path" { } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (image: drv: ''
        if [ -d "${drv}" ]; then
          ln -s "${drv}/${image}" "$out/${image}"
        else
          ln -s "${drv}" "$out/${image}"
        fi
      '') pds
    )}
  '';

  built =
    runCommand "${name}-system"
      {
        outputs = [
          "out"
          "report"
        ];

        passthru = {
          inherit
            board
            config
            searchPath
            sdk
            ;
          inherit (boardInfo) arch;
        };

        meta = {
          description = "seL4 Microkit system image '${name}' for ${board}";
          platforms = lib.platforms.linux;
        };
      }
      ''
        mkdir -p $out $report

        ${sdk}/bin/microkit ${systemFile} \
          --board ${board} \
          --config ${config} \
          --search-path ${searchPath} \
          -o $out/loader.img \
          -r $report/report.txt \
          ${lib.escapeShellArgs extraFlags}
      '';

  qemuRunner =
    if boardInfo ? qemu then
      writeShellApplication {
        name = "${name}-qemu";
        runtimeInputs = [ qemu ];
        text = ''
          exec ${boardInfo.qemu.binary} ${lib.escapeShellArgs (boardInfo.qemu.mkArgs "${built}/loader.img")} "$@"
        '';
      }
    else
      throw "nix-sel4: board '${board}' は QEMU で起動できません。実機向けに .image を書き込んでください";
in
lib.seq configOk (
  lib.seq imagesOk {
    image = built;
    report = built.report;
    qemu = qemuRunner;
    inherit
      boardInfo
      sdk
      searchPath
      ;
  }
)
