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

## Appending a byte range to a string without a slice of its own.

proc addChars*(s: var string, part: openArray[char]) =
  ## Append `part` without copying it into a string of its own first. Where
  ## `setLenUninit` exists and `s` already has the room, the room is not
  ## zeroed before the copy; a growth still zeroes it.
  if part.len > 0:
    let at = s.len
    when compiles(s.setLenUninit(0)):
      s.setLenUninit(at + part.len)
    else:
      s.setLen(at + part.len)
    copyMem(addr s[at], unsafeAddr part[0], part.len)
