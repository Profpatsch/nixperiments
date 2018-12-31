#!/usr/bin/env bash
# Inspired by:
# https://stackoverflow.com/a/29754866/1382925

function USAGE__ {
# TODO: EOF must not appear in interpolation
cat 1>&2 <<EOF
ERROR: $(echo -e $1)

myname: dis is description

myname
  --args (TYPE): argument description
EOF
exit 1
}

function CHECK_FILE__ {
    test -a "$1"
}

[[ $# -eq 0 ]] && USAGE__ "no arguments given"

PARSED__=$(getopt --name=myname --options= --longoptions=args:,script:,json: -- "$@")

# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED__"

# parse arguments, run checks, accumulate errors
ERRS__=
while true; do
  case "$1" in
    --args)
      CHECK_FILE__ "$2" \
        || ERRS__+="--args: file '$2' does not exist\n"
      args="$2"
      shift 2
      ;;
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
[[ "$ERRS__" != "" ]] \
  && USAGE__ "Argument errors:\n$ERRS__"

# check whether all options have been given
ERRS__=
for opt in args script json; do
  test -v args \
    || ERRS__+=" --${opt}"
done
[[ "$ERRS__" != "" ]] \
  && USAGE__ "options$ERRS__ are required"
  
# TODO: make sure these are not used as arguments
unset -v PARSED__ ERRS__
unset -f USAGE__
unset -f CHECK_FILE__