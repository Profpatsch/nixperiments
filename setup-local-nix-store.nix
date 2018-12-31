# Shell code to set up a local nix store
# for executing nix commands from a derivation.
# Intended for testing purposes.
{ pkgs
, withTests
, system ? pkgs.system
, nix ? pkgs.nix }:

let
  script = pkgs.writeText "local-nix-store.sh" ''
    datadir="${pkgs.nix}/share"
    export TEST_ROOT=$(pwd)/test-tmp
    export NIX_BUILD_HOOK=
    export NIX_CONF_DIR=$TEST_ROOT/etc
    export NIX_DB_DIR=$TEST_ROOT/db
    export NIX_LOCALSTATE_DIR=$TEST_ROOT/var
    export NIX_LOG_DIR=$TEST_ROOT/var/log/nix
    export NIX_MANIFESTS_DIR=$TEST_ROOT/var/nix/manifests
    export NIX_STATE_DIR=$TEST_ROOT/var/nix
    export NIX_STORE_DIR=$TEST_ROOT/store
    export PAGER=cat
    cacheDir=$TEST_ROOT/binary-cache
    ${nix}/bin/nix-store --init
  '';

  tests = let nixBin = "${pkgs.nix}/bin"; in {
    buildInLocalFolder = ''
      source ${script}
      love="I LOVE YOU"

      cat > builder <<EOF
      #!/bin/sh
      echo "$love"
      echo foo > \$out
      EOF
      chmod +x builder

      ${nixBin}/nix-instantiate \
        -E 'derivation { system = "${system}"; builder = ./builder; name = "foo"; }' \
        > drv

      # local store path is prefix of drv
      [[ $(cat drv) =~ $NIX_STORE_DIR ]]

      output=$(${nixBin}/nix-store --realize $(<drv))

      # the build outputs love
      ${nixBin}/nix-store --read-log "$output" | grep "$love"
    '';
  };

in withTests tests script
