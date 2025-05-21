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

import std/options

import independentutils, unicodeext

type
  JumpInfo* = object
    bufferId*: int # BufferStatus.id
    path*: Runes # File path
    position*: BufferPosition

  JumpList* = ref object
    currentPosition*: int # The current position of the jump history
    history*: seq[JumpInfo]

proc initJumpList*(): JumpList {.inline.} =
  return JumpList(currentPosition: -1, history: @[])

proc add*(l: var JumpList, bufferId: int, path: Runes, line, col: int) {.inline.} =
  l.history.add JumpInfo(
    bufferId: bufferId, path: path, position: BufferPosition(line: line, column: col)
  )
  l.currentPosition.inc

proc add*(
    l: var JumpList, bufferId: int, path: Runes, position: BufferPosition
) {.inline.} =
  l.history.add JumpInfo(bufferId: bufferId, path: path, position: position)
  l.currentPosition.inc

proc getCurrentHistoryPosition*(l: JumpList): Option[JumpInfo] =
  if l.history.len > 0 and l.currentPosition > -1:
    result = some(l.history[l.currentPosition])
    l.currentPosition.dec
