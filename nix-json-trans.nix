{ pkgs, libPath ? <nixpkgs/lib>
, script, setupLocalNixStore, withTests }:
# Scripts to transform json via nix eval.
# See the tests below for examples.

# TODO: Do we need all of lib?
let
  # Produce nix files that read the input files
  # and then call `nix eval`.
  transGeneric = name: synopsis: nixCommand:
    script.withOptions {
      inherit name synopsis;
      description = ''
        Similar to jq, but arguably more powerful.
        The nix script `trans` is a function that takes
        `args` as first argument (a nix attrset)
        and a `json` file as a nix value as second argument.
        `trans` has the <nixpkgs/lib> attrset in scope.
        Through `args` it is possible to pass e.g.
        nix store paths or files or more complex data.
      '';

      options = {
        args = {
          description = "Nix arguments to pass to the transformer.";
          checks = [ script.optionChecks.fileExists ];
        };
        trans = {
          description = "Nix JSON transformer function.";
          checks = [ script.optionChecks.fileExists ];
        };
        json = {
          description = "JSON input data";
          checks = [ script.optionChecks.fileExists ];
        };
      };

      script = ''
        #!${pkgs.stdenv.shell}
        # nix needs a path, containing / (`args` could be e.g. 'myfolder').
        ARGS="$(realpath "$args")"

        DIR=$(mktemp -d)
            # TODO: script-input should contain the name of `trans`
            # to ease debugging
        cat >$DIR/script-input.nix <<EOF
        with import ${
          # the concatenation with the root path # imports `libPath`
          # into the store, which is needed to make it work inside
          # of a nix build (we only have access to /nix/store)
          /. + libPath};
            $(cat "$trans")
        EOF

        JSON="$(realpath "$json")"

        cat >$DIR/script.nix <<EOF
        let
          args = import $ARGS;
          f = import $DIR/script-input.nix;
          json = builtins.fromJSON (builtins.readFile $JSON);
        in
          assert builtins.typeOf args == "set";
          assert builtins.typeOf f == "lambda";
          assert builtins.typeOf $JSON == "path";
          f args json
        EOF

        source ${setupLocalNixStore}
        ${nixCommand}
      '';
  };

  # `nix eval` call for json output
  json2json = transGeneric
    "nix-json-to-json"
    "Transform a json file using a nix expression."
    ''
      ${pkgs.nix}/bin/nix eval \
        --json \
        --show-trace \
        -f $DIR/script.nix \
        ""
    '';

  # `nix eval` call for plain text output
  json2string = transGeneric
    "nix-json-to-out"
    "Convert a json file to a string using a nix expression."
    ''
      ${pkgs.nix}/bin/nix eval \
        --raw \
        --show-trace \
        -f $DIR/script.nix \
        ""
    '';

  mkjson = json: pkgs.writeText "test.json" (builtins.toJSON json);

  jsonTests =
    let
      # compare json2json output with given result file
      eq = nixFile: jsonFile: resultFile: ''
        echo "{}" > ./args.nix
        ${pkgs.diffutils}/bin/diff \
          <(${json2json} \
              --args ./args.nix \
              --trans ${nixFile} \
              --json ${jsonFile}) \
          ${resultFile}
      '';
    in {

      # the identity function should produce the same output
      # we can compare bit-by-bit because the input is produced
      # by nix as well in this case
      idJson =
        let
          json = mkjson {
            foo = [ 1 2 3 null "bar" ];
          };
          idScr = pkgs.writeText "id-converter" "{}: id";
        in eq idScr json json;

      # we can apply library functions, like `mapAttrs`
      replaceAttrsJson =
        eq (pkgs.writeText "maybe-its-neuer"
              ''{}: mapAttrs (_: _: "manuel neuer")'')
          (mkjson { foo = "richard stallman"; bar = "linus torvalds"; })
          (mkjson { foo = "manuel neuer"; bar = "manuel neuer"; });
    };

  outTests = {

      # the string is echoed as-is
      buildEchoScriptFromJsonString = ''
        echo "{}" > ./args.nix
        echo "{}: str: str" > ./echo.nix
        ${json2string} \
          --args=./args.nix \
          --trans=./echo.nix \
          --json=${mkjson "hello!\nworld!"} \
            > out
          grep "hello!" <out
          grep "world!" <out
        '';

      # this one is interesting, we don’t transform at all
      # but rather use the fact that additional stuff can
      # be passed by args, e.g. store paths to executables
      passingArguments =
        let
          args = pkgs.writeText "args.nix" ''
            { shell = "${pkgs.stdenv.shell}"; }
          '';
          echoshell = pkgs.writeText "echoshell.nix" ''
            { shell }: _: '''
              #!''${shell}
              echo echoshell
            '''
          '';
        in ''
          touch empty.json
          # we produce a script in the `trans` expression,
          # print it, eval it and check its output
          ${json2string} \
            --args ${args} \
            --trans ${echoshell} \
            --json empty.json \
            | ${pkgs.stdenv.shell} -s \
            | grep echoshell
        '';
  };

in {
  json2json = withTests jsonTests json2json;
  json2string = withTests outTests json2string;
}
