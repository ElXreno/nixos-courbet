{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    linux = {
      url = "github:ElXreno/linux/courbet";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, linux, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      pkgsAarch64 = nixpkgs.legacyPackages.aarch64-linux;
      llvm = pkgs.llvmPackages_22;

      kbuildFlags = [
        "ARCH=arm64"
        "LLVM=1"
        "HOSTCC=gcc"
        "HOSTCXX=g++"
        "HOSTLDFLAGS=-fuse-ld=bfd"
      ];

      kernel = import ./kernel {
        inherit pkgs llvm kbuildFlags;
        src = linux;
      };

      bringup = import ./bringup {
        inherit
          pkgs
          pkgsAarch64
          llvm
          kernel
          ;
      };

      kmake = pkgs.writeShellScriptBin "kmake" ''
        exec make ${toString kbuildFlags} CC="ccache clang" "$@"
      '';
    in
    {
      packages.x86_64-linux = {
        inherit kernel;
        inherit (kernel) configfile;
        boot-img = bringup.bootImg;
        bringup-initramfs = bringup.initramfs;
        bringup-initramfs-bare = bringup.initramfsBare;
      };

      devShells.x86_64-linux.kernel = pkgs.mkShell {
        packages = [
          kmake
          bringup.mkboot
          llvm.clang-unwrapped
          llvm.lld
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
