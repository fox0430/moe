import std/os

type Bookmark* = object
  path*: string
  line*: int

proc addBookmark*(bookmarks: var seq[Bookmark], path: string, line: int) =
  for b in bookmarks:
    if b.path == path and b.line == line:
      return

  bookmarks.add Bookmark(path: path, line: line)

proc deleteBookmark*(bookmarks: var seq[Bookmark], path: string, line: int) =
  for i, b in bookmarks:
    if b.path == path and b.line == line:
      bookmarks.delete(i)

proc loadBookmarks*(): seq[Bookmark] =
  let
    chaheFile = getHomeDir() / ".cache/moe/bookmark"

  if fileExists(chaheFile):
    let f = open(chaheFile, FileMode.fmRead)
    while not f.endOfFile:
      let line = f.readLine
      echo line

proc saveBookmarks*(bookmarks: seq[Bookmark]) =
  let
    chaheDir = getHomeDir() / ".cache/moe"
    chaheFile = chaheDir / "bookmark"

  createDir(chaheDir)

  # Write to the file
  var f = open(chaheFile, FileMode.fmWrite)
  defer:
    f.close

  for line in bookmarks:
    f.writeLine($line)
