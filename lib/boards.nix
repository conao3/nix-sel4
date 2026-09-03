# Board metadata for the Microkit SDK.
#
# arch    : seL4 architecture, taken from CONFIG_SEL4_ARCH in the SDK headers.
# configs : build configurations the SDK ships for this board.
# qemu    : present when the board can be booted under QEMU. `mkArgs` receives
#           the path of the system image and returns the full argument list.
let
  # Both AArch64 QEMU boards boot the same way: QEMU provides EL2 and the
  # Microkit loader drops to EL1 when the kernel was built for it.
  aarch64Qemu = {
    package = "qemu";
    binary = "qemu-system-aarch64";
    mkArgs = image: [
      "-machine"
      "virt,virtualization=on"
      "-cpu"
      "cortex-a53"
      "-nographic"
      "-serial"
      "mon:stdio"
      "-device"
      "loader,file=${image},addr=0x70000000,cpu-num=0"
      "-m"
      "size=2G"
    ];
  };

  allConfigs = [
    "debug"
    "release"
    "benchmark"
    "smp-debug"
    "smp-release"
    "smp-benchmark"
  ];

  singleCoreConfigs = [
    "debug"
    "release"
    "benchmark"
  ];
in
{
  ariane = {
    arch = "riscv64";
    configs = singleCoreConfigs;
  };

  cheshire = {
    arch = "riscv64";
    configs = singleCoreConfigs;
  };

  hifive_p550 = {
    arch = "riscv64";
    configs = allConfigs;
  };

  imx8mm_evk = {
    arch = "aarch64";
    configs = allConfigs;
  };

  imx8mp_evk = {
    arch = "aarch64";
    configs = allConfigs;
  };

  imx8mp_iotgate = {
    arch = "aarch64";
    configs = allConfigs;
  };

  imx8mq_evk = {
    arch = "aarch64";
    configs = allConfigs;
  };

  kria_k26 = {
    arch = "aarch64";
    configs = singleCoreConfigs;
  };

  maaxboard = {
    arch = "aarch64";
    configs = allConfigs;
  };

  odroidc2 = {
    arch = "aarch64";
    configs = allConfigs;
  };

  odroidc4 = {
    arch = "aarch64";
    configs = allConfigs;
  };

  qemu_virt_aarch64 = {
    arch = "aarch64";
    configs = allConfigs;
    qemu = aarch64Qemu;
  };

  qemu_virt_aarch64_el1 = {
    arch = "aarch64";
    configs = allConfigs;
    qemu = aarch64Qemu;
  };

  qemu_virt_riscv64 = {
    arch = "riscv64";
    configs = allConfigs;
    qemu = {
      package = "qemu";
      binary = "qemu-system-riscv64";
      mkArgs = image: [
        "-machine"
        "virt"
        "-nographic"
        "-serial"
        "mon:stdio"
        "-kernel"
        image
        "-m"
        "size=2G"
      ];
    };
  };

  rock3b = {
    arch = "aarch64";
    configs = singleCoreConfigs;
  };

  rockpro64 = {
    arch = "aarch64";
    configs = allConfigs;
  };

  rpi4b_1gb = {
    arch = "aarch64";
    configs = allConfigs;
  };

  rpi4b_2gb = {
    arch = "aarch64";
    configs = allConfigs;
  };

  rpi4b_4gb = {
    arch = "aarch64";
    configs = allConfigs;
  };

  rpi4b_8gb = {
    arch = "aarch64";
    configs = allConfigs;
  };

  serengeti = {
    arch = "riscv64";
    configs = singleCoreConfigs;
  };

  star64 = {
    arch = "riscv64";
    configs = allConfigs;
  };

  stm32mp2 = {
    arch = "aarch64";
    configs = allConfigs;
  };

  tqma8xqp1gb = {
    arch = "aarch64";
    configs = allConfigs;
  };

  ultra96v2 = {
    arch = "aarch64";
    configs = allConfigs;
  };

  x86_64_generic = {
    arch = "x86_64";
    configs = allConfigs;
  };

  x86_64_generic_vtx = {
    arch = "x86_64";
    configs = allConfigs;
  };

  zcu102 = {
    arch = "aarch64";
    configs = allConfigs;
  };
}
