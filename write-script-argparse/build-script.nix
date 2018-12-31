{ stdenv, lib, writeText, writeScript, runCommand, utillinux }:
# Create a bash script and automatically generate an option parser.
# The option names are put into scope as plain bash variables.
{
  # script name
  # : string
  name,
  # short synopsis (shown in usage)
  # : string
  synopsis,
  # long (multi-line) description
  # : lines
  description ? "",
  # attrset of option names;
  # the key is used as name,
  # the value if of type
  # `{ description : string , checks : check }`
  # where `check` is of type
  # { fnName : string # check bash function name
  # , name : string # name displayed in usage
  # , code : lines # bash code of the check
  # }
  options,
  # bash script that has all options in scope
  # as variables of the same name
  # : lines
  script
}:
let
  # the usage text
  usage =
    let
      checks = lib.concatMapStringsSep ", " (c: c.name);
      usageAttr = n: v: "--${n} (${checks v.checks}): ${v.description}";
    in
      writeText "${name}-usage.txt" ''
        ${name}: ${synopsis}

        ${description}
        ${name}
          ${builtins.concatStringsSep "\n  "
              (lib.mapAttrsToList usageAttr options)}
      '';

  # bash function that prints usage to stderr
  usageFn = ''
    function USAGE__ {
    cat 1>&2 <<EOF
    ERROR: $(echo -e $1)

    $(cat ${usage})
    EOF
    exit 1
    }
  '';

  # all checks we are using in this script
  ourChecks =
    # we can remove duplicate checks because they are static
    lib.unique
      (builtins.concatLists
        (lib.mapAttrsToList (_: opt: opt.checks) options));

  # check bash functions
  checkFns =
    let
      checkFn = c: ''
        function ${c.fnName} {
        ${c.code}
        } '';
    in lib.concatMapStringsSep "\n" checkFn ourChecks;

  nameMapOptsSep = sep: f: lib.concatMapStringsSep sep f
                    (builtins.attrNames options);

  # bash getopt invocation
  getopt =
    let
      opts = nameMapOptsSep "," (o: "${o}:");
      getoptBin = runCommand "getopt-bin" {} ''
        install -D ${lib.getBin utillinux}/bin/getopt \
          $out/bin/getopt
      '';
    in ''
      PARSED__=$(${getoptBin}/bin/getopt --name="${name}" \
                  --options= \
                  --longoptions=${opts} \
                  -- "$@")

      # read getopt’s output this way to handle the quoting right:
      eval set -- "$PARSED__"
    '';

  # parsing the getopt output
  parseArguments =
    let
      # this is probably not very efficient …
      # a small embedding for indentation inside
      # lists of lists of strings
      rep = n: ch: builtins.foldl' (str: _: str + ch) ""
                     (builtins.genList lib.id n);
      indent = n: list: (map (s: (rep n " ") + s) list);
      i4 = indent 4;
      i2 = indent 2;
      # pure
      i0 = s: [s];
      # join
      embed = builtins.concatLists;
      applyIndent = builtins.concatStringsSep "\n";

      # a check inside an argument handler
      runCheck = argName: c: embed [
        (i0 ''${c.fnName} "$2" \'')
        (i2 (i0 ''|| ERRS__+="--${argName}: file '$2' does not exist\n"''))
      ];
      # generated argument handler for each option
      argHandler = name: opt: embed [
        (i0 ''--${name})'')
        (i2 (embed (map (runCheck name) opt.checks)))
        (i2 [
          ''${name}="$2"''
          ''shift 2''
          '';;''
        ])
      ];
    in ''
      # accumulate errors
      ERRS_=
      # parse getopt output
      while true; do
        case "$1" in
      ${applyIndent
          (i4 (embed (lib.mapAttrsToList argHandler options)))}
          --)
            shift
            # no further arguments
            [[ $# -ne 0 ]] \
              && ERRS__+="too many arguments: $@"
            break
            ;;
          *)
            ERRS__+="unknown argument: $1\n"
            shift 1
            ;;
        esac
      done
      # check if there were errors
      [[ "$ERRS__" != "" ]] \
        && USAGE__ "Argument errors:\n$ERRS__"
    '';

  # we abort on missing options
  checkAllOptionsGiven = ''
      # check whether all options have been given
      ERRS__=
    for opt in ${nameMapOptsSep " " lib.id}; do
        test -v $opt \
          || ERRS__+=" --$opt"
      done
      [[ "$ERRS__" != "" ]] \
        && USAGE__ "options$ERRS__ are required"
    '';

  # the optparser, which is sourced by the final script
  optParser = writeText "${name}-optparser.sh" ''
    # This is an automatically generated optparser.
    # It sets the following bash variables:
    # ${nameMapOptsSep ", " lib.id}
    # Inspired by:
    # https://stackoverflow.com/a/29754866/1382925

    ${usageFn}
    [[ $# -eq 0 ]] && USAGE__ "no arguments given"

    ${checkFns}
    ${getopt}
    ${parseArguments}
    ${checkAllOptionsGiven}

    # unset all variables, as to not lead to strange
    # effects in the following script
    unset -v PARSED__ ERRS__
    unset -f USAGE__
    unset -f ${lib.concatMapStringsSep " " (c: c.fnName) ourChecks}
  '';

  # the optparser is sourced because the generated code is quite long
  # and the actual script logic should not be shadowed by that.
  # TODO: maybe invert it, that you call the argparser yourself?
  finalScript = writeScript name ''
    #!${stdenv.shell}
    # call the argparser, which sets the following variables:
    # ${nameMapOptsSep ", " lib.id}
    source ${optParser}

    ${script}
  '';

in
  finalScript
