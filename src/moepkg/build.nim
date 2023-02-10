#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[os, osproc, strformat, unicode]
import syntax/highlite

proc build*(filename, workspaceRoot,
            command: seq[Rune],
            language: SourceLanguage): tuple[output: string, exitCode: int] =

  if language == SourceLanguage.langNim:
    let
      currentDir = getCurrentDir()
      workspaceRoot = workspaceRoot
      cmd = if command.len > 0: $command
            elif ($workspaceRoot).dirExists: fmt"cd {workspaceRoot} && nimble build"
            else: fmt"nim c {filename}"

    result = cmd.execCmdEx

    currentDir.setCurrentDir

  elif command.len > 0:
    let currentDir = getCurrentDir()

    result = ($command).execCmdEx

    if getCurrentDir() != currentDir: currentDir.setCurrentDir
