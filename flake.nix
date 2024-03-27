{
  inputs = {
    # a better way of using the latest stable version of nixpkgs
    # without specifying specific release
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/*.tar.gz";
  };

  outputs = { self, nixpkgs, ... }:
    let
      # helpers for producing system-specific outputs
      supportedSystems = [
        "aarch64-linux"
        "riscv64-linux"
        "x86_64-linux"
      ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f rec {
        pkgs = import nixpkgs {
          inherit system;

          overlays = [
            (final: prev: {
              linux_latest_with_llvm = prev.linux_latest.override {
                stdenv = llvmPkgs.stdenv;
              };
            })
          ];
        };

        llvmPkgs = pkgs.llvmPackages;
        # this gets the "major version" of LLVM, eg "16" or "17"
        llvmVersion = builtins.elemAt (builtins.splitVersion llvmPkgs.clang.version) 0;

        commonInputs = with pkgs; [
          # for a better kernel developer workflow
          b4
          dt-schema
          neovim
          yamllint

          # for "make menuconfig"
          pkg-config
          ncurses

          # testing the built kernel in a VM using QEMU
          debootstrap # fur creating ze rootfs
          gdb
          qemu_kvm

          # extra utilities _I_ find useful
          bat
          broot
          choose
          fd
          ripgrep

          # formatting this flake
          nixpkgs-fmt
        ];
      });

      globalBuildFlags = {
        # build related flags (for the script)
        CLEAN_BUILD = 0;
        INSTALL_ZE_KERNEL = 1;
      };
    in
    {
      devShells = forEachSupportedSystem ({ pkgs, commonInputs, llvmPkgs, llvmVersion, ... }: rec {
        default = withLLVM;
        #default = withGNU;

        withLLVM = (pkgs.mkShell.override { stdenv = llvmPkgs.stdenv; }) {
          inputsFrom = [ pkgs.linux_latest_with_llvm ];
          packages = commonInputs
            ++ [ pkgs.rustup ]
            # for some reason, `llvmPkgs.stdenv` does not have `lld` or actually `bintools`
            ++ [ llvmPkgs.bintools ];

          # Disable '-fno-strict-overflow' compiler flag because it causes the build to fail with the following error:
          # clang-16: error: argument unused during compilation: '-fno-strict-overflow' [-Werror,-Wunused-command-line-argument]
          hardeningDisable = [ "strictoverflow" ];

          env = rec {
            # just in case you want to disable building with the LLVM toolchain
            # **DO NOT SET THIS TO '0'**
            # **COMMENT IT OUT INSTEAD**
            # because, for some reason, setting `LLVM` to '0' still counts... :/
            LLVM = 1;
            # build related flags (for the script)
            BUILD_WITH_RUST = 0;

            # needed by Rust bindgen
            LIBCLANG_PATH = pkgs.lib.makeLibraryPath [ llvmPkgs.libclang.lib ];
            # because `grep gcc "$(nix-store -r $(command -v clang))/nix-support/libcxx-cxxflags"` matches
            # but `grep clang "$(nix-store -r $(command -v clang))/nix-support/libcxx-cxxflags"` **DOES NOT MATCH**
            KCFLAGS = "-isystem ${LIBCLANG_PATH}/clang/${llvmVersion}/include";
          } // globalBuildFlags;

          # **ONLY UNCOMMENT THIS IF YOU ARE _NOT_ USING HOME-MANAGER AND GET LOCALE ERRORS/WARNINGS**
          # If you are using home-manager, then add the following to your ~/.bashrc
          # `source $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh`
          #LOCALE_ARCHIVE_2_27 = "${pkgs.glibcLocales}/lib/locale/locale-archive";
        };

        withGNU = pkgs.mkShell {
          inputsFrom = [ pkgs.linux_latest ];
          packages = commonInputs;

          env = {
            # build related flags (for the script)
            BUILD_WITH_RUST = 0;
          } // globalBuildFlags;
        };
      });
    };
}
