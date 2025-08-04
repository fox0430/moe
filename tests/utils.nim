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

import std/[options, os, strutils]

import moepkg/[platform, editorstatus, ui, appinfo]

proc nimbleVersionStr(): string {.compileTime.} =
  const lines = staticExec("nimble -v").splitLines
  for l in lines:
    if l.startsWith("nimble v"):
      return l.split(" ")[1][1 ..^ 1]

  raise newException(ValueError, "Invalid nimble version")

proc nimbleVersion*(): VersionInfo {.compileTime.} =
  let splited = nimbleVersionStr().split(".")
  return VersionInfo(
    major: splited[0].parseInt, minor: splited[1].parseInt, patch: splited[2].parseInt
  )

proc isSkipNimbleVersion*(): bool =
  ## Workaround for https://github.com/nim-lang/nimble/issues/1384

  if getEnv("NOT_SKIP_TESTS") == "y":
    return false
  else:
    const NimbleVersion = nimbleVersion()
    return NimbleVersion.major == 0 and NimbleVersion.minor > 16

proc resize*(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

template isLasmAvailable*(): bool =
  execCmdEx("lasm --version").exitCode == 0

template isNphAvailable*(): bool =
  execCmdEx("nph --v").exitCode == 0

proc removeLineEnd*(buf: string): string =
  result = buf
  result.stripLineEnd

template setBufferToXsel*(buf: string): bool =
  execShellCmd("printf '" & buf & "' | xsel -pi") == 0

template setBufferToXclip*(buf: string): bool =
  execShellCmd("printf '" & buf & "' | xclip") == 0

template setBufferToWlClipboard*(buf: string): bool =
  execShellCmd("printf '" & buf & "' | wl-copy") == 0

template setBufferToWslDefaultClipboard*(buf: string): bool =
  execShellCmd("printf '" & buf & "' | powershell.exe -Command Get-Clipboard") == 0

template getXselBuffer*(): string =
  let r = execCmdEx("xsel -o")
  if r.exitCode != 0:
    assert false

  r.output

template getXclipBuffer*(): string =
  let r = execCmdEx("xclip -o")
  if r.exitCode != 0:
    assert false

  r.output

template getWlClipboardBuffer*(): string =
  let r = execCmdEx("wl-paste")
  if r.exitCode != 0:
    assert false

  r.output

template getWslDefaultBuffer*(): string =
  let r = execCmdEx("powershell.exe -Command Get-Clipboard")
  if r.exitCode != 0:
    assert false

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
