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

## The `+` arguments of the command line, Vim's `+{command}`.

import std/options

import regex_syntax

type
  StartupCommandKind* = enum
    sckEx ## `+{command}`: an Ex command, `+N` among them.
    sckSearch ## `+/pat`: the next line matching pat.

  StartupCommand* = object ## A `+` argument, run on the first file once it is read.
    case kind*: StartupCommandKind
    of sckEx:
      command*: string ## Without the `:`.
    of sckSearch:
      pattern*: string ## Empty repeats the last search.

proc parseStartupCommand*(arg: string): Option[StartupCommand] =
  ## The command a `+` argument names, none for one moe cannot run.
  let body = arg[1 .. ^1]
  if body.len == 0:
    # `+` alone is `+$`.
    return some(StartupCommand(kind: sckEx, command: "$"))
  if body[0] != '/':
    return some(StartupCommand(kind: sckEx, command: body))
  # Ex has no pattern address, so `+/pat` is a search of its own. The `/`
  # closing it is optional, as in Vim's `:/pat/`; nothing may follow it.
  let patternEnd = body.skipPattern(1)
  if patternEnd < body.high:
    return none(StartupCommand)
  some(StartupCommand(kind: sckSearch, pattern: body[1 ..< patternEnd]))
