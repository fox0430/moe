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

## Load-time checks shared by `[[Hook.entries]]` and `[[QuickRun.entries]]`:
## the command line and the keys that pick files.

import std/strutils

import pkg/[parsetoml, results]

import ../[command_string, file_command]

import base

proc hasEntryErrors*(vr: ValidationResult, label: string): bool =
  ## Whether a value under `label` was rejected (unknown keys excluded),
  ## so half-built entries are dropped.
  for issue in vr.errors:
    if issue.kind != sikUnknownKey and
        (issue.name == label or issue.name.startsWith(label & ".")):
      return true
  false

proc checkCommandLine*(
    t: TomlTableRef, command, label: string, vr: var ValidationResult
) =
  ## The `command` key `t` holds: non-empty, every quote closed, naming a
  ## program. A value of the wrong type is reported by its loader already.
  if command.strip.len == 0 and t["command"].kind == TomlValueKind.String:
    vr.addError(fullKey(label, "command"), "empty string", "non-empty command line")
    return
  let parsed = parseCommandString(command)
  if parsed.isErr:
    # Otherwise the quote runs to the end of the line, and a placeholder meant
    # as an argument to `sh -c` lands in its script.
    vr.addError(
      fullKey(label, "command"), command, "command line with every quote closed"
    )
  elif command.len > 0 and parsed.get.cmd.len == 0:
    # Quoted-but-empty program (`'' fmt`); report at load, not at exec.
    vr.addError(fullKey(label, "command"), command, "command line naming a program")

proc checkFileMatch*(
    entry: var FileCommandEntry, label: string, vr: var ValidationResult
) =
  ## Known file types and a compilable `filter`, compiled here once rather
  ## than per match.
  for i, name in entry.filetype:
    if not isValidFiletype(name):
      vr.addError(label & ".filetype[" & $i & "]", name, "known file type")

  let filterError = entry.compileFilter()
  if filterError.len > 0:
    vr.addError(fullKey(label, "filter"), entry.filter, "regex: " & filterError)
