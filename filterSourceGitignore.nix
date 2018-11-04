# This module implements a partial .gitignore parser
# for use in the nix evaluation phase.
# It is useful to filter out the same source files
# that your git implementation ignores, to get a clean
# build source when importing from a local folder
# with an unclean work tree (e.g. while developing).

# DIFFERENCES to `man 5 gitignore`:
# - Trailing spaces are not ignored.
# - Negations are not implemented (but recognized).
# - ** is not implemented.
# - * is only implemented if it is alone in a path segment.
# - ? is not implemented.
# - Bracketing with [] is not implemented.
# - The character \ is forbidden alltogether because we
#   did not want to implement escaping. Rename your files.

let
  lib = import <nixpkgs/lib>;

  # Throw away the regex matches in the result of `builtins.split`.
  onlySplitElems = builtins.filter (x: !builtins.isList x);

  # Split on `\n`.
  splitLines = str: onlySplitElems (builtins.split "\n" str);

  # Split on `/`.
  splitPathElems = str: onlySplitElems (builtins.split "/" str);

  # The nix evaluator only has a builtin for matching on perl regexes,
  # no support for real parsing. So we make due matching agains lines
  # of our .gitignore file in two steps:
  #
  # `matchLine` uses `lineMatchers` to filter out comments and empty lines,
  # and to fail on lines starting with `!`, which we don’t support.
  #
  # `toPathSpec` uses `pathElemMatchers` to convert eath path element
  # of the resulting pre-filtered expressions (split on `/`) into a
  # structured glob representation of that element.
  # It fails on unsupported characters, like `\`.

  lineMatchers = builtins.concatStringsSep "|" [
    ''(^$)''        # 0: empty string (is ignored)
    ''^(#).*''      # 1: comment (is ignored) (no escaping with \ implemented)
    ''^(!)(.*)''    # 2: possible inversion and 3: rest of line
    # will not enable a file starting with \#, but who cares …
    ''^\\([!#].*)'' # 4: escaped # or !
    ''(.+)''        # 5: anything else
  ];

  # Returns a pre-filtered line, or `""` if the line should be ignored.
  matchLine = l:
    let ignore = "";
        res = builtins.match lineMatchers l;
        at = builtins.elemAt res;
    in   if res == null then
      abort "matchLine: should not happen (nothing matched)"
    else if at 0 == ""  then ignore
    else if at 1 == "#" then ignore
    else if at 2 == "!" then
      abort ".gitignore negation not implemented (for line: ${l})"
    else let four = at 4;
      in if four != null then four
    else let five = at 5;
      in if five != null then five
    else abort "matchLine: should not happen (${toString res})";

  matchLineTests =
    let t = line: expected: {
        expr = matchLine line;
        inherit expected;
      };
    in lib.runTests {
      testEmpty = t "" "";
      testComment1 = t "#" "";
      testComment2 = t "# comment" "";
      # testInversion = t "!abc" "???";
      testNormal1 = t "abc" "abc";
      testNormal2 = t "/fo*/bar/" "/fo*/bar/";
    };


  pathElemMatchers = builtins.concatStringsSep "|" [
    ''(\*)''           # 0: a string with exactly one * is supported
    ''.*([[*?\]).*''   # 1: check for unsupported metacharacters
    # ''.*(\\*\\*).*'' # check for **, not supported
    ''(.*)''           # 2: anything else
  ];

  # GlobSpec:
  # sum
  #   { ignored : Unit,
  #   , glob : Glob
  #   }
  # Glob:
  # { isDir: Bool
  # , isRooted : Bool
  # , pathSpec : List PathSpec
  # }
  # PathSpec:
  # sum
  #  { glob : Unit
  #  , literal : String
  #  }

  # Convert an path element (path split on `/`) to a PathSpec.
  toPathSpec = elem:
    let res = builtins.match pathElemMatchers elem;
        at = builtins.elemAt res;
    in   if res == null then
      abort "toPathSpec: should not happen (nothing matched)"
    else if at 0 == "*" then { starGlob = {}; }
    else if at 1 != null then
      abort ''.gitignore: We don’t support these globbing metacharacters: ?\[*''
    else let two = at 2;
      in if two != null then { literal = two; }
    else abort "toPathSpec: should not happen (${toString res})";

  # Convert a line from a .gitignore file to a GlobSpec.
  toGlobSpec = line:
    # the line should be ignored
    if line == "" then { ignored = {}; }
    else
      let
        pathElems = splitPathElems line;
        isRooted = builtins.head pathElems == "";
        isDir = lib.last pathElems == "";
        snip = let
          one = if isRooted then builtins.tail pathElems else pathElems;
          two = if isDir then lib.init one else one;
          in two;
      in {
        glob = {
          inherit isDir isRooted;
          pathSpec = map toPathSpec snip;
        };
      };

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
  match = matcher: sum:
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
    matcher.${case} sum.${case};

  globSpecTests =
    let t = path: expected: {
          expr = toGlobSpec path;
          inherit expected;
        };
        ignored = { ignored = {}; };
        def = args: {
          glob = {
            isDir = false;
            isRooted = false;
            pathSpec = [];
          } // args;
        };
        lit = x: { literal = x; };
        starGlob = { starGlob = {}; };
    in lib.runTests {
      testIgnore = t "" ignored;
      testRoot = t "/" (def {
        isDir = true;
        isRooted = true;
        pathSpec = [ ];
      });
      # testDoubleGlob = t "foo**bar" "???";
      testDir = t "foo/" (def {
        isDir = true;
        pathSpec = [ (lit "foo") ];
      });
      testMultiPath = t "foo/bar/baz" (def {
        pathSpec = [ (lit "foo") (lit "bar") (lit "baz") ];
      });
      testGlobPath = t "/*/*/bar/*" (def {
        isRooted = true;
        pathSpec = [ starGlob starGlob (lit "bar") starGlob ];
      });
      testGlobEmptyPath = t "*//bar/*/" (def {
        isDir = true;
        pathSpec = [ starGlob (lit "") (lit "bar") starGlob ];
      });
    };

  # Predicate for whether `path` is matched by a Glob.
  # `pathIsDir` passes whether `path` is a directory (file otherwise)
  # ‘I have never been this boolean-blind.’
  pathMatchesGlob = pathIsDir: path: glob:
    let
      # split
      pathElems = splitPathElems path;
      pathElemsLen = builtins.length pathElems;
      globPathSpecLen = builtins.length glob.pathSpec;
      matchSpec = specElem: pathElem: match {
        literal = l: l == pathElem;
        starGlob = _: true;
      } specElem;
      # all path elements have to match the glob from the left
      matchPermutation = subPathElems:
           # files cannot match if the glob is shorter than the subpath
           (!glob.isDir -> globPathSpecLen == builtins.length subPathElems)
        && (builtins.all lib.id
             # the zip ensures that the longer list is cut to the
             # length of the shorter list; together with the length
             # check for file globs on the last line, this leads to
             # directories matching subpaths as well, e.g.
             # foo/bar/ matches /a/b/foo/bar/, but also /a/b/foo/bar/baz
             (lib.zipListsWith matchSpec glob.pathSpec subPathElems));
      # all permutations of applying the path are tested
      matchAllPermutations =
        let noOfPerms = 1 + pathElemsLen - globPathSpecLen;
        # if any matches, the whole path matches
        in lib.any matchPermutation
             # drop is also defined via genList, maybe there
             # is a better (more efficient) implementation
             (builtins.genList (i: lib.drop i pathElems) noOfPerms);
    in
       # a dir glob only matches a directory
       (glob.isDir -> pathIsDir)
       # if the glob has more elements than the path, we can return right away
    && (builtins.length glob.pathSpec <= builtins.length pathElems)
        # if the glob is rooted, we only match from the left
    && (if glob.isRooted
        then matchPermutation pathElems
        # else we have to match the glob over all subpaths
        else matchAllPermutations);

  pathMatchesGlobTest =
    let t = pathMatches: isDir: globString: path: {
          expr = pathMatchesGlob isDir path (toGlobSpec globString).glob;
          expected = pathMatches;
        };
        file = false;
        dir = true;
        y = t true; # matches
        n = t false; # does not match
    in lib.runTests {
      testRootFileGood = y file "/hi" "hi";
      testRootFileBad = n file "/hi" "hi-im-too-long";
      testRootFileIsDir = y dir "/hi" "hi";
      testRootDirGood = y dir "/hi/" "hi";
      testRootDirBad = n file "/hi/" "hi";
      # folder specs match all subfiles/folders
      testRootParentDirGood = y dir "/hi/" "hi/parent/matched";
      testRootParentDirBad = n dir "/hi/" "no/parent/matched";
      # a glob that is longer than the folder will never match
      testGlobTooLongFile = n file "/hi/im/too/*/long" "only/short";
      testGlobTooLongDir = n dir "/hi/im/too/*/long/" "only/short/dir";
      # one star glob matches one subpath
      testGlobSimple1 = y file "/hi/*/foo" "hi/im/foo";
      testGlobSimple2 = y file "/hi/*/foo" "hi/your/foo";
      testGlobSimple3 = n file "/hi/*/foo" "hi/your/notfoo";
      # tests for non-rooted files
      # we have to match those on every possible subpath
      testNonRootedGood1 = y file "hi" "hi";
      testNonRootedGood2 = y file "hi" "foo/bar/hi";
      testNonRootedBad = n file "hi" "foo/bar/nothi";
      testNonRootedDirGood = y dir "bar/*/hi/" "foo/bar/baz/hi/quux";
      testNonRootedDirBad = n dir "hi/*" "baz/nope/foo";
    };

  # takes a path to a .gitignore file, and a source directory,
  # and uses the .gitignore file as the predicate on which files
  # to copy to the nix store.
  filterSourceGitignore = gitignorePath: src:
    let
      # map, but removes elements for which f returns null
      mapMaybe = f: xs: builtins.filter (x: x != null) (map f xs);
      # turn path to glob, return all ignored lines
      globs = mapMaybe (p: match {
          ignored = _: null;
          glob = lib.id;
        } (toGlobSpec p))
        (splitLines (builtins.readFile gitignorePath));
      # the actual predicate that returns whether a file should be ignored
      shouldIgnore = path: type:
        assert lib.assertMsg (type != "unknown")
          ''filterSourceGitignore: file ${path} is of type "unknown"''
          + ", which we don’t support";
        # remove the absolute path prefix
        # of the parent dir of our gitignore
        # (the globs are relative to the gitignore file)
        let relPath = lib.removePrefix
              (toString (builtins.dirOf gitignorePath) + "/")
              (builtins.toString path);
        in
           # .git is always ignored by default
           (relPath == ".git")
           # if any glob matches, the file is ignored
        || builtins.any
             (pathMatchesGlob (type == "directory") relPath)
             globs;
    in builtins.filterSource (p: t: ! shouldIgnore p t) src;


# TODO: test suite
# in matchLineTests ++ globSpecTests ++ pathMatchesGlobTest
in filterSourceGitignore
