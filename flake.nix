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
            ] ++ zig-nixpkgs.lib.optionals zig-nixpkgs.stdenv.isDarwin [
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
              ${zig-nixpkgs.lib.optionalString zig-nixpkgs.stdenv.isDarwin ''
                export NIX_LDFLAGS="-F${zig-nixpkgs.darwin.apple_sdk.frameworks.CoreFoundation}/Library/Frameworks -framework CoreFoundation -L${zig-nixpkgs.darwin.libiconv}/lib $NIX_LDFLAGS"
              ''}
              zig build --prefix $out -Doptimize=ReleaseSafe
              runHook postBuild
            '';
            
            meta = {
              description = "A Zig-based CLI tool for stacked pull request workflows";
              homepage = "https://github.com/Orca-The-Company/sparse";
              license = zig-nixpkgs.lib.licenses.mit;
              maintainers = [];
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
