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

## The directories moe reads its own configuration from.

import std/os

when defined(posix):
  import std/posix

proc absoluteHomeDir(): string =
  ## The home dir. A relative HOME would point into the cwd, so the user
  ## database answers instead, or the root dir if that has no answer either.
  result = getHomeDir()
  if result.isAbsolute:
    return
  when defined(posix):
    let pw = getpwuid(getuid())
    if pw != nil and pw.pw_dir != nil:
      result = $pw.pw_dir
  if not result.isAbsolute:
    result = $DirSep

proc moeConfigDirs*(): seq[string] =
  ## The moe config dirs in search order: the XDG dir, then the home fallback.
  ## Never empty, and every one is absolute.
  let
    xdg = getConfigDir() / "moe"
    home = normalizedPath(absoluteHomeDir() / ".config" / "moe")
  # An empty or relative XDG_CONFIG_HOME is ignored, as the XDG spec says.
  # No `absolutePath`: it needs the cwd, which may have been deleted.
  if xdg.isAbsolute:
    result.add normalizedPath(xdg)
  if home notin result:
    result.add home
