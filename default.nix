{ nixpkgs ? import <nixpkgs> {} }:
let
  libPath = "${nixpkgs.path}/lib";
  pkgs = nixpkgs;
  lib = pkgs.lib;

in rec {
  match = import ./match.nix
    { inherit lib; };

  types = import ./simple-types
    { inherit lib; };

  filterSourceGitignore = import ./filterSourceGitignore.nix
    { inherit lib match; };

  filterSourceRegex = import ./filterSourceRegex.nix
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
    optionChecks
    argsChecks;
  };

  setupLocalNixStore = import ./setup-local-nix-store.nix
    { inherit pkgs withTests; };

  inherit (import ./nix-json-trans.nix {
             inherit pkgs libPath
                     script setupLocalNixStore
                     withTests;
          })
    json2json
    json2string;
}
