let
  lib = import <nixpkgs/lib>;

in rec {
  match = import ./match.nix
    { inherit lib; };

  filterSourceGitignore = import ./filterSourceGitignore.nix
    { inherit lib match; };

}
