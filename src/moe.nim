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

import moepkg/editor

proc main() =
  var app = newApp(
    AppConfig(
      title: "moe",
      alternateScreen: true,
      mouseCapture: false,
      rawMode: true,
      windowMode: true,
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
    false

  app.onRender proc(b: var Buffer) =
    editor.render(b)

  app.run()

when isMainModule:
  main()
