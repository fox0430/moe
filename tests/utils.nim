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

import std/[options, os, strutils]
import moepkg/[independentutils, platform]

proc removeLineEnd*(buf: string): string =
  result = buf
  result.stripLineEnd

template isXAvailable*(): bool =
  execCmdExNoOutput("xset q") == 0

template isWaylandAvailable*(): bool =
  let r = execCmdEx("echo $XDG_SESSION_TYPE")
  if r.exitCode != 0: assert false

  r.output.contains("wayland")

template isXselAvailable*(): bool =
  isXAvailable() and execCmdExNoOutput("xsel --version") == 0

template isXclipAvailable*(): bool =
  isXAvailable() and execCmdExNoOutput("xclip -version") == 0

template isWlClipboardAvailable*(): bool =
  isWaylandAvailable() and execCmdExNoOutput("wl-paste --version") == 0

template setBufferToXsel*(buf: string): bool =
  execShellCmd("printf '" & buf & "' | xsel -pi") == 0

template setBufferToXclip*(buf: string): bool =
  execShellCmd("printf '" & buf & "' | xclip") == 0

template setBufferToWlClipboard*(buf: string): bool =
  execShellCmd("printf '" & buf & "' | wl-copy") == 0

template setBufferToWslDefaultClipboard*(buf: string): bool =
  execShellCmd(
    "printf '" & buf & "' | powershell.exe -Command Get-Clipboard") == 0

template getXselBuffer*(): string =
  let r = execCmdEx("xsel -o")
  if r.exitCode != 0: assert false

  r.output

template getXclipBuffer*(): string =
  let r = execCmdEx("xclip -o")
  if r.exitCode != 0: assert false

  r.output

template getWlClipboardBuffer*(): string =
  let r = execCmdEx("wl-paste")
  if r.exitCode != 0: assert false

  r.output

template getWslDefaultBuffer*(): string =
  let r = execCmdEx("powershell.exe -Command Get-Clipboard")
  if r.exitCode != 0: assert false

  r.output

template clearXsel*(): bool =
  execShellCmd("printf '' | xsel") == 0

template clearXclip*(): bool =
  execShellCmd("printf '' | xclip") == 0

template clearWlClipboard*(): bool =
  execShellCmd("printf '' | wl-copy") == 0

template clearWslDefaultClipboard*(): bool =
  execShellCmd("printf '' | clip.exe") == 0

template isWsl*(): bool =
  getPlatform() == Platform.wsl
