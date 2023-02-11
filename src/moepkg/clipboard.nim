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

import std/[unicode, os]
import independentutils, platform, settings

proc runesToStrings(runes: seq[seq[Rune]]): string =
  if runes.len == 1:
    result = $runes[0]
  else:
    for i in 0 ..< runes.len:
      if i == 0:
        result = $runes[0]
      else:
        result &= "\n" & $runes[i]

proc sendToClipboard*(buffer: seq[seq[Rune]],
                      tool: ClipboardToolOnLinux) =

  if buffer.len < 1: return

  let
    str = runesToStrings(buffer)
    delimiterStr = genDelimiterStr(str)

  case currentPlatform:
    of linux:
      let cmd = if tool == ClipboardToolOnLinux.xclip:
                  "xclip -r <<" & "'" & delimiterStr & "'" & "\n" & str & "\n" & delimiterStr & "\n"
                elif tool == ClipboardToolOnLinux.xsel:
                  "xsel <<" & "'" & delimiterStr & "'" & "\n" & str & "\n" & delimiterStr & "\n"
                elif tool == ClipboardToolOnLinux.wlClipboard:
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
