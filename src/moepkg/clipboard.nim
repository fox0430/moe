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

import std/[os, osproc, strformat, strutils]
import pkg/results
import independentutils, platform, settings, unicodeext

proc linesToStrings(lines: seq[Runes]): string =
  result = lines.toString
  result.stripLineEnd

proc sendToClipboard*(
  buffer: seq[Runes],
  tool: ClipboardTool) =
    ## Send the buffer to the OS clipboard (xclip, xsel, etc).

    if buffer.len < 1: return

    let
      str = linesToStrings(buffer)
      delimiterStr = genDelimiterStr(str)

    case currentPlatform:
      of linux:
        let cmd =
          if tool == ClipboardTool.xclip:
            "xclip -r <<" & "'" & delimiterStr & "'" & "\n" & str & "\n" & delimiterStr & "\n"
          elif tool == ClipboardTool.xsel:
            "xsel <<" & "'" & delimiterStr & "'" & "\n" & str & "\n" & delimiterStr & "\n"
          elif tool == ClipboardTool.wlClipboard:
            "wl-copy <<" & "'" & delimiterStr & "'" & "\n" & str & "\n" & delimiterStr & "\n"
          else:
            ""

        if cmd.len > 0:
          discard execShellCmd(cmd)
      of wsl:
        let cmd = "clip.exe <<" & "'" & delimiterStr & "'" & "\n" & str & "\n"  & delimiterStr & "\n"
        discard execShellCmd(cmd)
      of mac:
        let cmd = "pbcopy <<" & "'" & delimiterStr & "'" & "\n" & str & "\n"  & delimiterStr & "\n"
        discard execShellCmd(cmd)
      else:
        discard

proc sendToClipboard*(buffer: Runes, tool: ClipboardTool) {.inline.} =
  ## Send the buffer to the OS clipboard (xclip, xsel, etc).

  sendToClipboard(@[buffer], tool)

proc getBufferFromClipboard*(tool: ClipboardTool): Result[Runes, string] =
  ## Return the buffer from the OS clipboard.

  if tool == none: return

  let cmd =
    case tool:
      of xsel: "xsel -o"
      of xclip: "xclip -o"
      of wlClipboard: "wl-paste"
      of wslDefault: "powershell.exe -Command Get-Clipboard"
      of macOsDefault: "pbpaste"
      else: ""

  let cmdResult = execCmdEx(cmd)
  if cmdResult.exitCode != 0:
    return Result[Runes, string].err fmt"clipboard: Failed to get clipboard buffer: {$cmdResult}"

  var buf = cmdResult.output
  buf.stripLineEnd
  return Result[Runes, string].ok buf.toRunes
