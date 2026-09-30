{
  pkgs,
  pkgsAarch64,
  llvm,
  kernel,
}:
let
  busybox = pkgsAarch64.pkgsStatic.busybox;

  cmdline = "console=tty0 loglevel=7 clk_ignore_unused pd_ignore_unused";

  mkbootimgArgs = toString [
    "--header_version 2"
    "--pagesize 4096"
    "--base 0x0"
    "--kernel_offset 0x8000"
    "--ramdisk_offset 0x01000000"
    "--tags_offset 0x100"
    "--dtb_offset 0x01f00000"
    "--os_version 16.0.0"
    "--os_patch_level 2026-09"
  ];

  rebootBootloader =
    pkgs.runCommand "reboot-bootloader"
      {
        nativeBuildInputs = [
          llvm.clang-unwrapped
          llvm.lld
        ];
      }
      ''
        clang --target=aarch64-linux-gnu -static -nostdlib -ffreestanding -O2 -fuse-ld=lld \
          -o $out ${./reboot-bootloader.c}
      '';

  modules = pkgs.makeModulesClosure {
    kernel = kernel.modules;
    firmware = pkgs.emptyDirectory;
    rootModules = [
      "ath10k_snoc"
      "nvmem_qcom-spmi-sdam"
      "qcom-spmi-adc5"
      "qcom-spmi-temp-alarm"
      "qcom_glink_smem"
      "qcom_pd_mapper"
      "qcom_q6v5_pas"
      "qcom_qg"
      "qcom_smbx"
      "qrtr-smd"
    ];
  };

  mkInitramfs =
    name: withModules:
    pkgs.runCommand name
      {
        nativeBuildInputs = [
          pkgs.cpio
          pkgs.gzip
          pkgs.kmod
          pkgs.zstd
        ];
      }
      ''
        mkdir -p root/{bin,dev,etc,proc,sys,tmp,var}
        cp ${busybox}/bin/busybox root/bin/busybox
        install -m 0755 ${rebootBootloader} root/bin/reboot-bootloader
        install -m 0755 ${./init} root/init
        ${pkgs.lib.optionalString withModules ''
          cp -r --no-preserve=mode ${modules}/lib root/lib
          find root/lib/modules -name '*.ko.zst' -exec zstd -dq --rm {} +
          depmod -b root ${kernel.modDirVersion}
        ''}
        (cd root && find . -print0 | sort -z | cpio --null -o -H newc --reproducible --owner=0:0) | gzip -9n >$out
      '';

  initramfs = mkInitramfs "bober-bringup-initramfs" true;
  initramfsBare = mkInitramfs "bober-bringup-initramfs-bare" false;
in
{
  inherit initramfs initramfsBare;

  bootImg = pkgs.runCommand "bober-boot.img" { nativeBuildInputs = [ pkgs.android-tools ]; } ''
    mkbootimg ${mkbootimgArgs} \
      --kernel ${kernel}/Image.gz \
      --dtb ${kernel}/dtbs/qcom/sm7150-xiaomi-courbet.dtb \
      --ramdisk ${initramfs} \
      --cmdline "${cmdline}" \
      -o $out
  '';

  mkboot = pkgs.writeShellScriptBin "mkboot" ''
    exec ${pkgs.android-tools}/bin/mkbootimg ${mkbootimgArgs} \
      --kernel "$1" --dtb "$2" -o "$3" --ramdisk "''${4:-${initramfsBare}}" \
      --cmdline "''${BOOT_CMDLINE:-${cmdline}}"
  '';
}
