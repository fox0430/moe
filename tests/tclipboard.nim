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

proc isXAvailable(): bool {.inline.} =
  execCmdExNoOutput("xset q") == 0

proc isXselAvailable(): bool {.inline.} =
  isXAvailable() and execCmdExNoOutput("xsel --version") == 0

proc isXclipAvailable(): bool {.inline.} =
  isXAvailable() and execCmdExNoOutput("xclip -version") == 0

if isXselAvailable():
  suite "Clipboard: Send to clipboad (xsel)":
    test "Send string to clipboard 1 (xsel)":
      const
        Buffer = @[ru "Clipboard test"]
        Tool = ClipboardToolOnLinux.xsel

      sendToClipboard(Buffer, Tool)

      let p = initPlatform()
      if p == Platforms.linux or p == Platforms.wsl:
        let
          cmd =
            if p == Platforms.linux:
              execCmdEx("xsel -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $Buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $Buffer

    test "Send string to clipboard 1 (xclip)":
      const
        Buffer = @[ru "Clipboard test"]
        Tool = ClipboardToolOnLinux.xclip

      sendToClipboard(Buffer, Tool)

      let p = initPlatform()
      if p == Platforms.linux or p == Platforms.wsl:
        let
          cmd =
            if p == Platforms.linux:
              execCmdEx("xclip -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $Buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $Buffer

    test "Send string to clipboard 2 (xsel)":
      const
        Buffer = @[ru "`````"]
        Tool = ClipboardToolOnLinux.xsel

      sendToClipboard(Buffer, Tool)

      let p = initPlatform()
      if p == Platforms.linux or p == Platforms.wsl:
        let
          cmd =
            if p == Platforms.linux:
              execCmdEx("xsel -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $Buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $Buffer

if isXclipAvailable():
  suite "Clipboard: Send string to clipboard (xclip)":
    test "Send string to clipboard (xclip)":
      const
        Buffer = @[ru "`````"]
        Tool = ClipboardToolOnLinux.xclip

      sendToClipboard(Buffer, Tool)

      let p = initPlatform()
      if p == Platforms.linux or p == Platforms.wsl:
        let
          cmd =
            if p == Platforms.linux:
              execCmdEx("xclip -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $Buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $Buffer

    test "Send string to clipboard 2 (xsel)":
      const
        Buffer = @[ru "$Clipboard test"]
        Tool = ClipboardToolOnLinux.xsel

      sendToClipboard(Buffer, Tool)

      let p = initPlatform()
      if p == Platforms.linux or p == Platforms.wsl:
        let
          cmd =
            if p == Platforms.linux:
              execCmdEx("xsel -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $Buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $Buffer

    test "Send string to clipboard 3 (xclip)":
      const
        Buffer = @[ru "$Clipboard test"]
        Tool = ClipboardToolOnLinux.xclip

      sendToClipboard(Buffer, Tool)

      let p = initPlatform()
      if p == Platforms.linux or p == Platforms.wsl:
        let
          cmd =
            if p == Platforms.linux:
              execCmdEx("xclip -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0
        if p == Platforms.linux:
          check output[0 .. output.high - 1] == $Buffer
        else:
          # On the WSL
          check output[0 .. output.high - 2] == $Buffer
