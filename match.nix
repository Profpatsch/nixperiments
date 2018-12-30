{ lib }:
# The canonical pattern matching primitive.
# A sum value is an attribute set with one element,
# whose key is the name of the variant and
# whose value is the content of the variant.
# `matcher` is an attribute set which enumerates
# all possible variants as keys and provides a function
# which handles each variant’s content.
# You should make an effort to return values of the same
# type in your matcher, or new sums.
#
# Example:
#   let
#      success = { res = 42; };
#      failure = { err = "no answer"; };
#      matcher = {
#        res = i: i + 1;
#        err = _: 0;
#      };
#    in
#       match matcher success == 43
#    && match matcher failure == 0;
#
matcher: sum:
let cases = builtins.attrNames sum;
in assert
  let len = builtins.length cases; in
    lib.assertMsg (builtins.length cases == 1)
      ( "match: an instance of a sum is an attrset "
      + "with exactly one element, yours had ${toString len}"
      + ", namely: ${lib.generators.toPretty {} cases}" );
let case = builtins.head cases;
in assert
    lib.assertMsg (matcher ? ${case})
    ( "match: \"${case}\" is not a valid case of this sum, "
    + "the matcher accepts: ${lib.generators.toPretty {}
        (builtins.attrNames matcher)}" );
matcher.${case} sum.${case}
