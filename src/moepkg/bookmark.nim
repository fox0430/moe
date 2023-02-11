#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

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
