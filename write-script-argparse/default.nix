{ callPackage }:

let
  # main documentation in here
  withOptions = callPackage ./build-script.nix {};

  # A list of checks that can be passed to `script.withOptions`.
  optionChecks = {
    fileExists = {
      fnName = "FILE_EXISTS__";
      name = "FILE";
      code = ''test -a "$1"'';
    };
  };

  # TODO: nice tests
  tests = {
    foo = withOptions {
      name = "myname";
      synopsis = "dis is synopsis";
      options = {
        args = {
          description = "argument description";
          checks = [ optionChecks.fileExists ];
        };
        json = {
          description = "some json!";
          checks = [];
        };
      };
      script = ''
        echo $args
        echo $json
      '';
    };
  };

in {
  inherit withOptions optionChecks;
}
