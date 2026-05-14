{
  description = "JokeWall Basecamp UI plugin — Qt6 C++ + Rust FFI";

  inputs = {
    logos-nix.url = "github:logos-co/logos-nix";
    nixpkgs.follows = "logos-nix/nixpkgs";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    nix-bundle-lgx = {
      url = "github:logos-co/nix-bundle-lgx";
      inputs.logos-nix.follows = "logos-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, logos-nix, rust-overlay, flake-utils, nix-bundle-lgx }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        rustToolchain = pkgs.rust-bin.stable.latest.default;

        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };

        # ── ZK circuit artifacts ──────────────────────────────────────────────
        logosCiruits = pkgs.fetchurl {
          url = "https://github.com/logos-blockchain/logos-blockchain-circuits/releases/download/v0.4.2/logos-blockchain-circuits-v0.4.2-linux-x86_64.tar.gz";
          sha256 = "13c5gkfsa70kca0nwffbsis2difmspyk8aqmlzhq12mhr3x1y4z9";
        };

        circuitsDir = pkgs.runCommand "logos-blockchain-circuits" {} ''
          mkdir -p $out
          tar -xzf ${logosCiruits} -C $out --strip-components=1
        '';

        # ── LEZ source (nssa build.rs artifacts) ──────────────────────────────
        # Must match the nssa tag used in ui/ffi/Cargo.toml (v0.2.0-rc3).
        # Run `nix-prefetch-git --url https://github.com/logos-blockchain/logos-execution-zone.git \
        #   --rev cf3639d8252040d13b3d4e933feb19b42c76e14a` to get the sha256.
        lezSrc = pkgs.fetchgit {
          url = "https://github.com/logos-blockchain/logos-execution-zone.git";
          rev = "cf3639d8252040d13b3d4e933feb19b42c76e14a";
          hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # UPDATE ME
        };

        # ── Rust FFI cdylib ────────────────────────────────────────────────────
        ffi = rustPlatform.buildRustPackage {
          pname = "joke-wall-ffi";
          version = "0.1.0";
          src = ./ffi;

          cargoLock = {
            lockFile = ./ffi/Cargo.lock;
            outputHashes = {
              # Update these hashes after running `cargo build --release` in ui/ffi/
              # to generate ui/ffi/Cargo.lock, then re-run `nix build .#ffi`.
              "amm_core-0.1.0"                          = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
              "jf-crhf-0.1.1"                           = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
              "jf-poseidon2-0.1.0"                      = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
              "logos-blockchain-blend-crypto-0.1.2"     = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
              "overwatch-0.1.0"                         = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            };
          };

          LOGOS_BLOCKCHAIN_CIRCUITS = "${circuitsDir}";

          preBuild = ''
            ln -sf "${lezSrc}/artifacts" ../cargo-vendor-dir/artifacts
          '';

          doCheck = false;
        };

        # ── Qt6 C++ plugin ─────────────────────────────────────────────────────
        plugin = pkgs.stdenv.mkDerivation {
          pname = "joke-wall-plugin";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
            pkgs.qt6.wrapQtAppsHook
          ];

          buildInputs = with pkgs.qt6; [
            qtbase
            qtdeclarative
          ];

          cmakeFlags = [
            "-DJOKE_WALL_FFI_LIB_DIR=${ffi}/lib"
          ];

          installPhase = ''
            runHook preInstall
            cmake --install .
            cp ${./manifest.json} $out/manifest.json
            cp ${./metadata.json} $out/metadata.json
            cp -r ${./qml} $out/qml
            runHook postInstall
          '';
        };

        # ── Install helper ─────────────────────────────────────────────────────
        installScript = pkgs.writeShellScriptBin "install-joke-wall-plugin" ''
          PLUGIN_DIR="$HOME/.local/share/Logos/LogosBasecampDev/plugins/joke_wall"
          mkdir -p "$PLUGIN_DIR"
          cp -f ${plugin}/lib/libjoke_wall_plugin.so  "$PLUGIN_DIR/"
          cp -f ${plugin}/lib/libjoke_wall_ffi.so     "$PLUGIN_DIR/"
          cp -f ${plugin}/manifest.json               "$PLUGIN_DIR/"
          cp -f ${plugin}/metadata.json               "$PLUGIN_DIR/"
          echo "Installed to $PLUGIN_DIR"
        '';

        lgx = nix-bundle-lgx.bundlers.${system}.portable plugin;

      in {
        packages = {
          default = plugin;
          ffi     = ffi;
          install = installScript;
          lgx     = lgx;
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            rustToolchain
            pkgs.cmake pkgs.ninja pkgs.pkg-config
            pkgs.qt6.wrapQtAppsHook
          ];
          buildInputs = with pkgs.qt6; [ qtbase qtdeclarative ];
          shellHook = ''
            echo "joke-wall UI dev shell"
            echo "  cmake, ninja, Qt6, Rust all on PATH"
            echo "  Build FFI:    cargo build --release (in ffi/)"
            echo "  Build plugin: cmake -B build -GNinja && cmake --build build"
          '';
        };
      });
}
