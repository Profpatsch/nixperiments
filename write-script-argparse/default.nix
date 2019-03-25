{ callPackage }:

let
  # main documentation in here
  withOptions = callPackage ./build-script.nix {};

  # A number of checks that can be passed to `script.withOptions`.

  # checks for `options.<name>.checks`
  # all of these are kind of racey, but ¯\_(ツ)_/¯
  optionChecks = {
    # option is a path to file that exists
    fileExists = {
      fnName = "FILE_EXISTS__";
      name = "FILE";
      code = ''[ -e "$2" ] || ERRS_add__ "$1: file $2 does not exist"'';
    };
    # option is a path with no existing file
    emptyPath = {
      fnName = "EMPTY_PATH__";
      name = "EMPTY_PATH";
      code = ''[ ! -e "$2" ] || ERRS_add__ "$1: $2 should be an empty path"'';
    };
    # option is a directory
    isDir = {
      fnName = "IS_DIR__";
      name = "DIR";
      code = ''[ -d $(realpath "$2") ] || ERRS_add "Not a directory: $1"'';
    };
  };

  # checks for `extraArgs.checks`
  argsChecks = {

    # First argument is an executable file (not a directory)
    firstArgIsExecutable = {
      fnName = "FIRST_ARG_IS_EXECUTABLE__";
      code = ''
        local f=$(realpath "$1")
        [[ -f "$f" && -x "$f" ]] || ERRS_add__ "Not executable: $1
      '';
    };

    # TODO: fancey map over all arguments?
    # check that all args are existing directories
    allAreDirs = {
      fnName = "ALL_ARGS_ARE_DIRS__";
      code = ''
        for arg in "$@"; do
          [ -d $(realpath "$arg") ] || ERRS_add__ "Not a directory: $arg"
        done
      '';
    };
  };

  # TODO: nice tests
  tests = {
    foo = withOptions {
      name = "myname";
      synopsis  = "dis is synopsis";
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
      # extraArguments = {
      #   description = "program to exec into";
      #   name = "PROG";
      #   itemChecks = 
      # };
      script = ''
        echo $args
        echo $json
      '';
    };
  };

in {
  inherit withOptions optionChecks argsChecks;
}
