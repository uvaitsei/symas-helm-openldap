{
  description = "A Helm Chart for OpenLDAP.";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs/23.11";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    inputs.utils.lib.eachSystem
      [
        "x86_64-linux"
        "i686-linux"
        "aarch64-linux"
        "x86_64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ ];
            config.allowUnfree = true;
          };
        in
        {
          flake-utils.inputs.systems.follows = "system";
          formatter = with pkgs; [ nixfmt ];
          devShells.default = import ./shell.nix { inherit pkgs; };
          DOCKER_BUILDKIT = 1;
        }
      );
}
