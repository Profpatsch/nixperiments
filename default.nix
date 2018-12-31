{ nixpkgs ? <nixpkgs> }:
let
  lib = import "${toString nixpkgs}/lib";
  pkgs = import nixpkgs {};

in rec {
  match = import ./match.nix
    { inherit lib; };

  filterSourceGitignore = import ./filterSourceGitignore.nix
    { inherit lib match; };

  inherit (import ./package-tests {
             inherit (pkgs) runCommand;
             inherit lib;
          })
    drvSeq
    drvSeqL
    withTests;

  script = {
    inherit (import ./write-script-argparse {
               inherit (pkgs) callPackage;
            })
    withOptions
    optionChecks;
  };
}
