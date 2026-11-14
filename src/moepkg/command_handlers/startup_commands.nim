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

## Runs the `+` arguments of the command line, as Vim's exe_commands runs its
## `+{command}` and `-c` commands on the first file.

import std/options

import
  ../[
    editor, editor_file_jobs, editor_notify, buffer, types, search_ops, startup_command
  ]
import editor_ops, handler_result, result_processor

proc searchStartLine(e: Editor, pattern: string, aboveFirst: bool): bool =
  ## Go to the next line matching `pattern`, wrapping around, which becomes
  ## the last search as Vim's `:/pat` makes it; from the first line when
  ## `aboveFirst`. An empty one repeats the last search. Whether it found one.
  let spec = e.state.submitSearch(pattern, Forward)
  if spec.isNone:
    return false
  let
    buffer = e.activeBuffer
    start =
      if aboveFirst:
        0
      else:
        (e.cursor.line + 1) mod max(buffer.len, 1)
    # A negative column takes the start line whole.
    found = e.state.findCountedMatch(
      buffer, spec.get, BufferPosition(line: start, column: -1), 1
    )
  if found.isNone:
    e.state.statusMessage = e.state.missedSearchMessage(spec.get)
    return false
  # Not a jump, as `+N` and Vim's `:/pat` are not.
  e.processGotoLineResult(
    HandlerResult(kind: hrGotoLine, lineNumber: found.get.line + 1), buffer
  )
  true

proc runStartupCommands*(e: Editor, commands: openArray[StartupCommand]) =
  ## Run the `+` arguments in the active window, in order. What they say goes
  ## below what the status line already shows, such as a config error, and
  ## one does not replace another. A command that quits ends the run and the
  ## session, as a typed one does.
  if commands.len == 0:
    return
  # As in exe_commands, a cursor on the first line stands above it until a
  # command moves it, so `+/pat` finds a match on the first line.
  var aboveFirst = e.cursor.line == 0
  for command in commands:
    # Each command logs its message as a typed one does; only the status
    # line is joined here.
    let shown = e.state.statusMessage
    e.state.setStatusQuiet("")
    var moved, quit: bool
    # One command, as a typed one is.
    e.asCommand:
      let before = e.cursor
      case command.kind
      of sckEx:
        # As with -c, the command line history does not get it.
        quit = e.executeCommandOverlay(":" & command.command, history = false) == roQuit
        moved = e.cursor != before
      of sckSearch:
        moved = e.searchStartLine(command.pattern, aboveFirst)
    let said = e.state.statusMessage
    e.state.setStatusQuiet(shown)
    if said.len > 0:
      e.showBelowStatus(said)
    if moved:
      aboveFirst = false
    if quit:
      e.beginQuit()
      break
  # The file tree opens on the first frame and narrows the windows, so they
  # are placed again then, as for a remembered position.
  if e.config.startUpFileTree.enable:
    for window in e.windowManager.windows:
      window.viewport.resetViewportTop()
