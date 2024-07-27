#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[json, strformat, strutils, times]

import lsp/client
import ui, unicodeext, messagelog, highlight

type
  LogContentKind* = enum
    editor
    lsp

proc countLogLine[T](buf: T): int =
  ## `buf` is `seq[Runes]`, `GapBuffer[T]` or etc

  if buf.len == 1 and buf[0].len == 0: return 0

  result = 1
  for i in 0 .. buf.high:
    # Count empty lines after log lines.
    if buf[i].len == 0: result.inc

proc initEditorLogViewrBuffer*(): seq[Runes] =
  let log = getMessageLog()

  if log.len == 0:
    return @[ru""]

  for i, l in log:
    result.add l
    if i < log.high:
      result.add ru""

proc initLspLogViewrBuffer*(log: LspLog): seq[Runes] =
  if log.len == 0:
    return @[ru""]

  for i in 0 .. log.high:
    result.add toRunes(fmt"{$log[i].timestamp} -- {$log[i].kind}")

    let lines = log[i].message.pretty.splitLines.toSeqRunes
    for i in 0 .. lines.high: result.add lines[i]

    if i < log.high: result.add ru""

proc initLogViewerHighlight*(buffer: seq[Runes]): Highlight =
  ## TODO: Move to highlight module?

  if buffer.len > 0:
    const EmptyReservedWord: seq[ReservedWord] = @[]
    return buffer.initHighlight(EmptyReservedWord, SourceLanguage.langNone)

proc isUpdateEditorLogViwer*[T](buf: var T): bool {.inline.} =
  ## `buf` is `seq[Runes]`, `GapBuffer[T]` or etc

  return messageLogLen() > buf.countLogLine

proc isUpdateLspLogViwer*[T](buf: var T, log: var LspLog): bool {.inline.} =
  ## `buf` is `seq[Runes]`, `GapBuffer[T]` or etc

  log.len > buf.countLogLine

proc isLogViewerCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if isCtrlK(key) or
       isCtrlJ(key) or
       key == ord(':') or
       key == ord('k') or isUpKey(key) or
       key == ord('j') or isDownKey(key) or
       key == ord('h') or isLeftKey(key) or isBackspaceKey(key) or
       key == ord('l') or isRightKey(key) or
       key == ord('0') or isHomeKey(key) or
       key == ord('$') or isEndKey(key) or
       key == ord('q') or isEscKey(key) or
       key == ord('G'):
         return InputState.Valid
    elif key == ord('g'):
      return InputState.Continue
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        return InputState.Valid
