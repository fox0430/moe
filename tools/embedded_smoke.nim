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

## Compile and runtime smoke test for Moe's embedding surface.

import pkg/results

import ../src/moepkg/[clipboard_backend, frontend, types]
import ../src/moepkg/command_handlers/editor_ops

when defined(windows):
  import ../src/moepkg/uri_utils
  import ../src/moepkg/command_handlers/[file_ops, handler_result]
  import ../src/moepkg/types/editor_types

static:
  doAssert defined(moe.embedded)
  doAssert not declared(TerminalState)
  doAssert not declared(newTerminalState)
  doAssert not declared(newTerminal)
  doAssert not declared(AsyncApp)

let config = newEditorConfig()
doAssert not config.clipboard.enable

let clipboardRead = readFromClipboardSync(config.clipboard.tool)
doAssert clipboardRead.isErr

when defined(windows):
  let openUriResult = openExternalUri("https://example.com")
  doAssert openUriResult.isErr
  doAssert openUriResult.error ==
    "Opening external URIs is unavailable in embedded mode on Windows"

let editor = newEditor(config)

when defined(windows):
  discard editor.processFileResult(
    HandlerResult(kind: hrOpenUri, openUri: "https://example.com"), editor.activeBuffer
  )
  doAssert editor.state.statusMessage ==
    "Opening external URIs is unavailable in embedded mode on Windows"

editor.enterTerminalInActiveWindow("")
doAssert editor.state.statusMessage == "Terminal mode is unavailable in embedded builds"
