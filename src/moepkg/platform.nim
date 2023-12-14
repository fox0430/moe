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

import std/[osproc, strutils]
import independentutils

type
  Platform* = enum
    ## Operating system
    linux
    wsl
    mac
    freebsd
    openbsd
    other

  Gui* {.pure.} = enum
    ## GUI environment.
    console
    x11
    wayland
    other

proc initPlatform(): Platform =
  if defined linux:
    if execProcess("uname -r").contains("microsoft"):
      return Platform.wsl
    else:
      return Platform.linux
  elif defined macosx:
    return Platform.mac
  elif defined freebsd:
    return Platform.freebsd
  elif defined openbsd:
    return Platform.openbsd
  else:
    return Platform.other

proc getXdgSessionType(): string =
  let r = execCmdEx("echo $XDG_SESSION_TYPE")
  if r.exitCode == 0: return r.output

proc isX11*(): bool {.inline.} =
  if getXdgSessionType().contains("x11"): return true
  else: return execCmdExNoOutput("xset q") == 0

proc isWayland*(): bool {.inline.} =
  getXdgSessionType().contains("wayland")

proc initGui(platform: Platform): Gui =
  case platform:
    of mac, wsl:
      return Gui.other
    else:
      if isWayland(): return Gui.wayland
      elif isX11(): return Gui.x11
      else: return Gui.console

let
  platform = initPlatform()
  gui = initGui(platform)

proc getPlatform*(): Platform {.inline.} = platform

proc getGuiEnv*(): Gui {.inline.} = gui
