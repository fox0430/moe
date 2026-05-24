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

import std/[options, unittest, strutils]

import ../src/moepkg/cmdline {.all.}
import ../src/moepkg/config

suite "cmdline - CmdLineConfig":
  test "default CmdLineConfig values":
    let config = CmdLineConfig()
    check config.debugEnabled == false
    check config.isReadonly == false
    check config.filePaths.len == 0
    check config.bufferBackend.isNone

suite "cmdline - parseBufferBackendArg":
  test "auto":
    check parseBufferBackendArg("auto") == bbcAuto
  test "gapBuffer":
    check parseBufferBackendArg("gapBuffer") == bbcGapBuffer
  test "sqrtDecomp":
    check parseBufferBackendArg("sqrtDecomp") == bbcSqrtDecomp
  test "rope":
    check parseBufferBackendArg("rope") == bbcRope
  test "pieceTable":
    check parseBufferBackendArg("pieceTable") == bbcPieceTable

suite "cmdline - generateVersionInfoMessage":
  test "message contains moe version prefix":
    let msg = generateVersionInfoMessage()
    check msg.startsWith("moe v")

  test "message contains Git hash label":
    let msg = generateVersionInfoMessage()
    check "Git hash:" in msg

  test "message contains Build type label":
    let msg = generateVersionInfoMessage()
    check "Build type:" in msg

  test "message contains version in semver format":
    let msg = generateVersionInfoMessage()
    # First line should be "moe vX.Y.Z"
    let firstLine = msg.split('\n')[0]
    check firstLine.startsWith("moe v")
    let version = firstLine[5 .. ^1] # after "moe v"
    let parts = version.split('.')
    check parts.len == 3
