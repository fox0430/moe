#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[strformat, osproc, strutils]

import pkg/results

import unicodeext, highlight, color

proc initDiffViewerBuffer*(
    sourceFilePath, backupFilePath: string
): Result[seq[Runes], string] =
  let cmdResult = execCmdEx(fmt"diff -u {sourceFilePath} {backupFilePath}")
  if cmdResult.exitCode == 2:
    # The diff command return 2 on failure.
    return Result[seq[Runes], string].err "diff command failed"

  var r = @[ru""]
  for line in cmdResult.output.splitLines:
    r.add line.toRunes

  return Result[seq[Runes], string].ok r

proc initDiffViewerHighlight*(buffer: seq[Runes]): Highlight =
  for i, line in buffer:
    let color =
      if line.len > 0 and line[0] == ru '+':
        EditorColorPairIndex.diffViewerAddedLine
      elif line.len > 0 and line[0] == ru '-':
        EditorColorPairIndex.diffViewerDeletedLine
      else:
        EditorColorPairIndex.default

    result.colorSegments.add(
      ColorSegment(
        firstRow: i, firstColumn: 0, lastRow: i, lastColumn: line.high, color: color
      )
    )

proc initDiffViewerHighlight*(buffer: Runes): Highlight =
  return initDiffViewerHighlight(buffer.splitLines)
