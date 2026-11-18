#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## How a path is spelled on the screen. Not for telling files apart: that is
## `path_key`'s.

import std/[options, os, strutils]

var homeDirs: Option[seq[string]]
  ## `$HOME` and the path it resolves to, read on first use

proc homePrefixes(): lent seq[string] =
  ## The prefixes Vim's `home_replace` shows as `~`: `$HOME` as written and,
  ## when it goes through a link, its real path.
  if homeDirs.isNone:
    var dirs: seq[string]
    # Not getHomeDir: it gives "/" for an empty $HOME.
    let raw =
      when defined(posix):
        getEnv("HOME")
      else:
        getHomeDir()
    var home = raw.strip(leading = false, chars = {DirSep})
    if home.len == 0 and raw.len > 0:
      # A root home: Vim shows the root itself as `~` and nothing under it.
      home = $DirSep
    if home.len > 0:
      dirs.add home
      try:
        let real = expandFilename(home)
        if real != home:
          dirs.add real
      except OSError:
        discard
    homeDirs = some(dirs)
  homeDirs.get

proc homeReplace*(path: string, homes: openArray[string] = homePrefixes()): string =
  ## `path` with a leading home directory shown as `~`, as Vim's
  ## `home_replace`: only the home itself or a path under it.
  for home in homes:
    if home.len > 0 and path.startsWith(home) and
        (path.len == home.len or path[home.len] == DirSep):
      return "~" & path[home.len .. ^1]
  path
