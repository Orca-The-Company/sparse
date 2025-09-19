{
  description = "Dev environment for sparse";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    # 0.14.0
    zig-nixpkgs.url = "github:NixOS/nixpkgs/f6db44a8daa59c40ae41ba6e5823ec77fe0d2124";
    # 1.9.0
    # libgit2-nixpkgs.url = "github:NixOS/nixpkgs/f6db44a8daa59c40ae41ba6e5823ec77fe0d2124";
  };

  outputs =
    {
      self,
      flake-utils,
      zig-nixpkgs,
    }@inputs:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        zig-nixpkgs = inputs.zig-nixpkgs.legacyPackages.${system};

        # Pre-fetch libgit2 source
        libgit2-src = zig-nixpkgs.fetchFromGitHub {
          owner = "libgit2";
          repo = "libgit2";
          rev = "v1.9.0";
          hash = "sha256-v32yGMo5oFEl6HUdg8czCsCLDL+sy9PPT0AEWmKxUhk=";
        };

        # Pre-fetch mbedtls wrapper source
        mbedtls-src = zig-nixpkgs.fetchFromGitHub {
          owner = "allyourcodebase";
          repo = "mbedtls";
          rev = "7d862fe61ff2eac37ee54e1e017fc287bed1cd7a";
          hash = "sha256-YYKZm9WNXIid+9phQVAUfjWVu29KxBSnmWpeV50v1jw=";
        };

        # Pre-fetch actual mbedtls source
        mbedtls-actual-src = zig-nixpkgs.fetchFromGitHub {
          owner = "Mbed-TLS";
          repo = "mbedtls";
          rev = "mbedtls-3.6.2";
          hash = "sha256-CigOAezxk79SSTX6Z7rDnt64qI6nkCD0piY9ZVNy+e0=";
        };
      in
      {
        packages = rec {
          default = sparse;

          sparse = zig-nixpkgs.stdenv.mkDerivation rec {
            pname = "sparse";
            version = "0.0.0";

            src = zig-nixpkgs.lib.cleanSource ./.;

            patches = [
              ./nix/patches/0001-nix-build-compatibility.patch
            ];

            nativeBuildInputs = [
              zig-nixpkgs.zig
              zig-nixpkgs.pkg-config
            ];

            buildInputs = [
              zig-nixpkgs.openssl
            ]
            ++ zig-nixpkgs.lib.optionals zig-nixpkgs.stdenv.isDarwin [
              zig-nixpkgs.darwin.apple_sdk.frameworks.Security
              zig-nixpkgs.darwin.apple_sdk.frameworks.CoreFoundation
              zig-nixpkgs.darwin.apple_sdk.frameworks.SystemConfiguration
              zig-nixpkgs.darwin.libiconv
            ];

            dontConfigure = true;

            buildPhase = ''
              runHook preBuild
              export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
              mkdir -p $ZIG_GLOBAL_CACHE_DIR

              # Prepare the libgit2 source in the expected location
              mkdir -p $ZIG_GLOBAL_CACHE_DIR/p
              cp -r ${libgit2-src} $ZIG_GLOBAL_CACHE_DIR/p/N-V-__8AAJbmLwHHxHDWkz0i6WIR6FpNe6tXSLzaPuWtvBBg

              # Prepare the mbedtls wrapper source in the expected location
              cp -r ${mbedtls-src} $ZIG_GLOBAL_CACHE_DIR/p/mbedtls-3.6.2-E4NURzYUAABWLBwHJWx_ppb_j2kDSoGfCfR2rI2zs9dz

              # Prepare the actual mbedtls source (needed by the wrapper)
              cp -r ${mbedtls-actual-src} $ZIG_GLOBAL_CACHE_DIR/p/N-V-__8AAPnFhALfI8HonTAfQwJlGPkOdcv9kdkvnmLlJDJo

              chmod -R u+w $ZIG_GLOBAL_CACHE_DIR

              ${zig-nixpkgs.lib.optionalString zig-nixpkgs.stdenv.isDarwin ''
                export NIX_LDFLAGS="-F${zig-nixpkgs.darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks -framework CoreFoundation -L${zig-nixpkgs.darwin.libiconv}/lib $NIX_LDFLAGS"
              ''}
              # zig build --prefix $out -Doptimize=ReleaseSafe
              zig build --prefix $out
              runHook postBuild
            '';

            meta = {
              description = "A Zig-based CLI tool for stacked pull request workflows";
              homepage = "https://github.com/Orca-The-Company/sparse";
              license = zig-nixpkgs.lib.licenses.mit;
              maintainers = [ ];
              platforms = zig-nixpkgs.lib.platforms.unix;
              mainProgram = "sparse";
            };
          };
        };

        devShells.default = zig-nixpkgs.mkShell {
          packages = [
            zig-nixpkgs.zig
            zig-nixpkgs.openssl
          ];

          shellHook = ''
            echo "zig" "$(zig version)"
          '';
        };
      }
    );
}
