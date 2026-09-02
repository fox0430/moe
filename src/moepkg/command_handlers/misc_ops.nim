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

## Small misc side effects (search highlight, whitespace strip, shell /
## background / man / build pending ops, theme), split out of
## result_processor.nim.

import std/os

import ../[editor, logger, registers, types]

import editor_ops, handler_result

proc processMiscResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool =
  ## Handle misc side-effect kinds. Returns true to continue.
  case r.kind
  of hrClearSearchHighlight:
    e.state.input.search.hlsearch = false
    return true
  of hrStripWhitespace:
    let count = r.strippedLineCount
    if count > 0:
      e.state.statusMessage = "Stripped trailing whitespace from " & $count & " lines"
    else:
      e.state.statusMessage = "No trailing whitespace found"
    return true
  of hrShellCommand:
    e.state.pending.add PendingAsyncOp(kind: paoShellCommand, command: r.shellCommand)
    return true
  of hrBackground:
    e.state.pending.add PendingAsyncOp(kind: paoBackground)
    return true
  of hrMan:
    e.state.pending.add PendingAsyncOp(kind: paoManPage, command: r.hrManPage)
    return true
  of hrSubstitute:
    let count = r.hrSubstituteCount
    e.state.statusMessage = $count & " substitution" & (if count == 1: "" else: "s")
    return true
  of hrDeleteLines:
    e.state.registers.setDeletedRegister(r.hrDeletedText, true)
    let count = r.hrDeletedLineCount
    e.state.statusMessage =
      $count & " line" & (if count == 1: "" else: "s") & " deleted"
    # Vim leaves the cursor on the line that followed the deleted range, which is
    # now its start line. A fold can widen the range above the old cursor line.
    let maxLine = e.activeBuffer().len - 1
    e.activeWindow.cursor.line = min(max(0, r.hrDeleteStartLine), maxLine)
    e.activeWindow.cursor.column = 0
    return true
  of hrBuild:
    let filePath = if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: ""
    if filePath.len == 0:
      e.state.statusMessage = "Build error: File not saved"
      logError("handler", "Build failed: No file path")
    else:
      e.state.pending.add PendingAsyncOp(
        kind: paoBuild,
        build: (
          path: filePath,
          language: activeBuffer.language.ord,
          customCmd: "",
          workspaceRoot: parentDir(filePath),
        ),
      )
      e.state.statusMessage = "Building: " & filePath
    return true
  of hrTheme:
    e.applyThemeCommand(r.hrThemeName)
    return true
  else:
    return true # Not a misc kind; caller misrouted (defensive)
