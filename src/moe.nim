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

import std/[os, strformat]

import pkg/[celina, results]

import moepkg/[editor, handler, modes]

proc main() =
  var app = newApp(
    AppConfig(
      title: "moe",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
    )
  )

  let editor = newEditor()

  if paramCount() > 0:
    let path = paramStr(1)

    block:
      let r = editor.loadFile(path)
      if r.isErr:
        echo fmt"Error: {r.error}"
        quit(1)

  app.onEvent proc(e: Event): bool =
    editor.handleEvent(e)
    return true # Always return true to prevent app exit on unhandled keys

  app.onRender proc(b: var Buffer) =
    # Update editor view
    editor.render(b)

    # Set cursor style based on editor mode
    case editor.state.mode
    of EditorMode.Insert:
      app.setCursorStyle(CursorStyle.SteadyBar) # I-beam cursor for Insert mode
    of EditorMode.Normal:
      app.setCursorStyle(CursorStyle.SteadyBlock) # Block cursor for Normal mode
    of EditorMode.Command:
      app.setCursorStyle(CursorStyle.SteadyUnderline) # Underline cursor for Command mode

    # Set cursor position from calculated screen coordinates
    app.setCursor(editor.state.cursor.x, editor.state.cursor.y)

  app.run()

when isMainModule:
  main()
