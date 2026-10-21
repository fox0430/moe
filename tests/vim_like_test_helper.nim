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

## An editor that types as `vim -u NONE` does, and keys written as in Vim, for
## the tests measured against Vim.

import std/[options, strutils]

import ../src/moepkg/[buffer, types, registers, editor, config, key_bindings]

proc newVimLikeEditor*(
    lines: seq[string],
    line, column: int,
    autoIndent = false,
    expandTab = false,
    tabStop = 8,
    shiftWidth = 0,
): Editor =
  ## An editor typing as `vim -u NONE` with these options does: no pair is
  ## closed or deleted, and 'shiftwidth' 0 follows 'tabstop'.
  var config = newEditorConfig()
  config.standard.autoIndent = autoIndent
  config.standard.autoCloseParen = false
  config.standard.autoDeleteParen = false
  config.standard.expandTab = expandTab
  config.standard.tabStop = tabStop
  config.standard.shiftWidth = shiftWidth
  result = newEditor(config)
  # newEditor's registers reach the system clipboard.
  result.state.registers = initRegisters()
  let buffer = newTextBuffer(lines.join("\n") & "\n")
  result.windowManager.windows[0].setTab(buffer)
  result.windowManager.windows[0].bufferIds = @[buffer.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.motionController.bindToWindow(result.activeWindow)
  result.state.mode = EditorMode.Normal
  result.activeWindow.cursor = BufferPosition(line: line, column: column)

proc keysOf*(spec: string): seq[KeyCombo] =
  ## `<Name>` is one key (`<Escape>`, `<C-u>`), any other character a key, and
  ## so is a `<` that starts no key name, as the first of Vim's `<<Escape>`.
  var i = 0
  while i < spec.len:
    let
      close =
        if spec[i] == '<':
          spec.find('>', i)
        else:
          -1
      name =
        if close > i + 1:
          spec[i + 1 ..< close]
        else:
          ""
      key =
        if name == "C-@":
          # Ctrl-@ arrives as NUL, which celina reports as Ctrl+Space.
          some(KeyCombo(isSpecial: false, char: " ", modifiers: {kmCtrl}))
        elif name.len > 0 and '<' notin name:
          parseKeyCombo(name)
        else:
          none(KeyCombo)
    if key.isSome:
      result.add key.get
      i = close + 1
    else:
      result.add(KeyCombo(isSpecial: false, char: $spec[i]))
      inc i

proc lines*(e: Editor): seq[string] =
  for i in 0 ..< e.activeBuffer.len:
    result.add e.activeBuffer.getLine(i)
