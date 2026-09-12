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

## Splitting a command line into an argv the process starter can use.
##
## Used by build-on-save, which takes a command as one string from the config
## and must exec it without a shell.

type CommandArgv* = tuple[cmd: string, args: seq[string]]

proc parseCommandString*(cmdStr: string): CommandArgv =
  ## Parse a command string into a CommandArgv tuple, honoring POSIX-style
  ## single/double quotes and backslash escapes so args containing whitespace
  ## survive as a single token.
  ## E.g., `nim c "-d:foo bar" file.nim` -> (cmd: "nim", args: @["c", "-d:foo bar", "file.nim"])
  var
    tokens: seq[string] = @[]
    current = ""
    inSingle = false
    inDouble = false
    hasToken = false
    i = 0
  while i < cmdStr.len:
    let c = cmdStr[i]
    if inSingle:
      if c == '\'':
        inSingle = false
      else:
        current.add c
    elif inDouble:
      if c == '"':
        inDouble = false
      elif c == '\\' and i + 1 < cmdStr.len and cmdStr[i + 1] in {'"', '\\'}:
        current.add cmdStr[i + 1]
        inc i
      else:
        current.add c
    else:
      case c
      of ' ', '\t':
        if hasToken:
          tokens.add current
          current = ""
          hasToken = false
      of '\'':
        inSingle = true
        hasToken = true
      of '"':
        inDouble = true
        hasToken = true
      of '\\':
        if i + 1 < cmdStr.len:
          current.add cmdStr[i + 1]
          inc i
        else:
          current.add c
        hasToken = true
      else:
        current.add c
        hasToken = true
    inc i
  if hasToken or inSingle or inDouble:
    tokens.add current

  if tokens.len == 0:
    return (cmd: "", args: @[])
  elif tokens.len == 1:
    return (cmd: tokens[0], args: @[])
  else:
    return (cmd: tokens[0], args: tokens[1 .. ^1])
