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

## Single canonical spelling for file paths, so comparisons do not depend on
## how the path was typed (relative vs absolute, `~`, `.` segments).

import std/os

proc pathKey*(path: string): string {.raises: [].} =
  ## Tilde-expanded, absolute, normalized form of `path`. Never raises.
  if path.len == 0:
    return ""
  try:
    normalizedPath(absolutePath(expandTilde(path)))
  except ValueError, OSError:
    # Fall back to the raw spelling when there is nothing to resolve against.
    normalizedPath(path)

proc samePath*(a, b: string): bool {.raises: [].} =
  ## Whether `a` and `b` name the same file. Empty paths match nothing.
  if a.len == 0 or b.len == 0:
    return false
  pathKey(a) == pathKey(b)
