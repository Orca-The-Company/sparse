{
  description = "Dev environment for sparse";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    # 0.14.0
    zig-nixpkgs.url = "github:NixOS/nixpkgs/f6db44a8daa59c40ae41ba6e5823ec77fe0d2124";
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
        devShells.default = zig-nixpkgs.mkShell {
          packages = [
            zig-nixpkgs.zig
            # zig-nixpkgs.openssl
            # zig-nixpkgs.mbedtls
            # zig-nixpkgs.llhttp
            zig-nixpkgs.libgit2
          ];

          shellHook = ''
            echo "zig" "$(zig version)"
          '';
        };
      }
    );
}
