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

import ../src/moepkg/[clipboard_backend, frontend, terminal_mode]

static:
  doAssert defined(moe.embedded)

let config = newEditorConfig()
doAssert not config.clipboard.enable

let clipboardRead = readFromClipboardSync(config.clipboard.tool)
doAssert clipboardRead.isErr

let terminal = newTerminalState()
doAssert terminal.isErr

discard newEditor(config)
