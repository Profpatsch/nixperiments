{ lib, match }:
{
  sanityChecks ? []
}:
filterRegexes:
src:

let
  # traverse an item of type T topologically.
  # returns a List T
  topoTraverse =
    # T -> List T -- unfold an item into its next layer
    unfoldList:
    # T -> Bool -- whether to recurse further on an item
    pred:
    # T -- the start item
    tree:
    let
      work = unfoldList tree;
      moreWork = builtins.filter pred work;
    in work ++ lib.concatMap (topoTraverse unfoldList pred) moreWork;

  # builtins.readDir, but recurses into directories.
  # returns List { path, type }
  # where path is the full path of a file
  # and type is its type like returned from builtins.readDir
  readDirRecursively =
    # whether to recurse into a directory
    recurseDirPred:
    # the directory to read
    dir:
    topoTraverse
    # run builtins.readDir to get the next level
    (dir: lib.mapAttrsToList (basename: type: {
        path = (toString dir.path) + "/" + (toString basename);
        inherit type;
      })
      (builtins.readDir dir.path))
    # only recurse when it’s a directory and the predicate matches
    (x: x.type == "directory" && recurseDirPred x.path)
    # initial value
    { path = dir; type = "directory"; };

  removePrefixDir = prefixDir: path: lib.removePrefix (toString prefixDir + "/") path;

  traceIf = msg: v: if v then builtins.trace msg v else v;
  matchesAnyRegex = why: path: lib.any (regex: traceIf "matches regex ${regex} in ${why}: ${path}" (builtins.match regex path != null)) filterRegexes;

# TODO: this is inefficient.
# filterSource will queue all subfiles if you return "true" for a directory!
# So it should be given a list of sub-path regexes instead!
in builtins.filterSource
    (path: type: builtins.trace path (
      if type == "directory"
      # we can only include the whole thing, even if only a subset matches :(
      # that’s a restriction of builtins.filterSource
      then lib.any
        (matchesAnyRegex "dir")
        (map (x: removePrefixDir src x.path) (readDirRecursively (dir: ! matchesAnyRegex "recurse?" dir) path))
      else matchesAnyRegex "not a dir" (removePrefixDir src path)))
      # TODO: return *why* something matched
      src
