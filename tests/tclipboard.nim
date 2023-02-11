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

import std/[unittest, osproc]
import moepkg/[settings, unicodeext, clipboard]

import moepkg/platform {.all.}
import moepkg/independentutils {.all.}

proc isXselAvailable(): bool {.inline.} =
  execCmdExNoOutput("xset q") == 0 and execCmdExNoOutput("xsel --version") == 0

proc isXclipAvailable(): bool {.inline.} =
  execCmdExNoOutput("xset q") == 0 and execCmdExNoOutput("xclip -version") == 0

if isXselAvailable():
  suite "Editor: Send to clipboad (xsel)":
    test "Send string to clipboard 1 (xsel)":
      const
        buffer = @[ru "Clipboard test"]
        tool = ClipboardToolOnLinux.xsel

      sendToClipboard(buffer, tool)

      let p = initPlatform()
      if (p == Platforms.linux or
          p == Platforms.wsl):
        let
          cmd = if p == Platforms.linux:
                  execCmdEx("xsel -o")
                else:
                  # On the WSL
                  execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $buffer

    test "Send string to clipboard 1 (xclip)":
      const
        buffer = @[ru "Clipboard test"]
        tool = ClipboardToolOnLinux.xclip

      sendToClipboard(buffer, tool)

      let p = initPlatform()
      if (p == Platforms.linux or
          p == Platforms.wsl):
        let
          cmd = if p == Platforms.linux:
                  execCmdEx("xclip -o")
                else:
                  # On the WSL
                  execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $buffer

    test "Send string to clipboard 2 (xsel)":
      const
        buffer = @[ru "`````"]
        tool = ClipboardToolOnLinux.xsel

      sendToClipboard(buffer, tool)

      let p = initPlatform()
      if (p == Platforms.linux or
          p == Platforms.wsl):
        let
          cmd = if p == Platforms.linux:
                  execCmdEx("xsel -o")
                else:
                  # On the WSL
                  execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $buffer

if isXclipAvailable():
  suite "Send string to clipboard (xclip)":
    test "Send string to clipboard (xclip)":
      const
        buffer = @[ru "`````"]
        tool = ClipboardToolOnLinux.xclip

      sendToClipboard(buffer, tool)

      let p = initPlatform()
      if (p == Platforms.linux or
          p == Platforms.wsl):
        let
          cmd = if p == Platforms.linux:
                  execCmdEx("xclip -o")
                else:
                  # On the WSL
                  execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $buffer

    test "Send string to clipboard 2 (xsel)":
      const
        buffer = @[ru "$Clipboard test"]
        tool = ClipboardToolOnLinux.xsel

      sendToClipboard(buffer, tool)

      let p = initPlatform()
      if (p == Platforms.linux or
          p == Platforms.wsl):
        let
          cmd = if p == Platforms.linux:
                  execCmdEx("xsel -o")
                else:

                  # On the WSL
                  execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $buffer

    test "Send string to clipboard 3 (xclip)":
      const
        buffer = @[ru "$Clipboard test"]
        tool = ClipboardToolOnLinux.xclip

      sendToClipboard(buffer, tool)

      let p = initPlatform()
      if (p == Platforms.linux or
          p == Platforms.wsl):
        let
          cmd = if p == Platforms.linux:
                  execCmdEx("xclip -o")
                else:

                  # On the WSL
                  execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $buffer
