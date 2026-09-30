{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      llvm = pkgs.llvmPackages;

      kmake = pkgs.writeShellScriptBin "kmake" ''
        exec make ARCH=arm64 LLVM=1 HOSTCC=gcc HOSTCXX=g++ HOSTLDFLAGS=-fuse-ld=bfd CC="ccache clang" "$@"
      '';

      busybox = nixpkgs.legacyPackages.aarch64-linux.pkgsStatic.busybox;

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
              -o $out ${./bringup/reboot-bootloader.c}
          '';

      bringupInitramfs =
        pkgs.runCommand "bober-bringup-initramfs"
          {
            nativeBuildInputs = [
              pkgs.cpio
              pkgs.gzip
            ];
          }
          ''
            mkdir -p root/{bin,dev,etc,proc,sys,tmp,var}
            cp ${busybox}/bin/busybox root/bin/busybox
            install -m 0755 ${rebootBootloader} root/bin/reboot-bootloader
            install -m 0755 ${./bringup/init} root/init
            (cd root && find . -print0 | sort -z | cpio --null -o -H newc --reproducible --owner=0:0) | gzip -9n >$out
          '';

      mkboot = pkgs.writeShellScriptBin "mkboot" ''
        exec ${pkgs.android-tools}/bin/mkbootimg --header_version 2 --pagesize 4096 --base 0x0 \
          --kernel_offset 0x8000 --ramdisk_offset 0x01000000 --tags_offset 0x100 --dtb_offset 0x01f00000 \
          --os_version 16.0.0 --os_patch_level 2026-09 \
          --kernel "$1" --dtb "$2" -o "$3" --ramdisk "''${4:-${bringupInitramfs}}" \
          --cmdline "''${BOOT_CMDLINE:-console=tty0 loglevel=7 clk_ignore_unused pd_ignore_unused}"
      '';
    in
    {
      packages.x86_64-linux.bringup-initramfs = bringupInitramfs;

      devShells.x86_64-linux.kernel = pkgs.mkShell {
        packages = [
          kmake
          mkboot
          llvm.clang-unwrapped
          pkgs.llvmPackages_22.lld
          llvm.llvm
          pkgs.android-tools
          pkgs.bc
          pkgs.bison
          pkgs.ccache
          pkgs.cpio
          pkgs.dtc
          pkgs.flex
          pkgs.kmod
          pkgs.lz4
          pkgs.ncurses
          pkgs.perl
          pkgs.pkg-config
          pkgs.python3
        ];

        buildInputs = [
          pkgs.elfutils
          pkgs.openssl
          pkgs.zlib
        ];

        hardeningDisable = [ "all" ];

        env.CCACHE_DIR = "/mnt/scratch/ccache";
      };
    };
}
