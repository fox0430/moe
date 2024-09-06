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

import std/options

import lsp/documentsymbol
import unicodeext, editorstatus, bufferstatus, messages, gapbuffer

proc jumpToSymbol(status: var EditorStatus, symbolName: Runes) =
  # LSP Document Symbol

  var symbol: Option[DocumentSymbol]
  for s in currentBufStatus.documentSymbols:
    if s.name == $symbolName:
      symbol = some(s)
      break

  if symbol.isNone:
    status.commandLine.writeLspDocumentSymbolError("Not found")

  if symbol.get.range.isNone:
    status.commandLine.writeLspDocumentSymbolError("Unknown position")

  let dest = symbol.get.range.get.start

  currentMainWindowNode.currentLine = min(
    dest.line,
    currentBufStatus.buffer.high)
  currentMainWindowNode.currentColumn = min(
    dest.character,
    currentBufStatus.buffer[dest.line].high)

proc execDocumentSymbolCommand*(
  status: var EditorStatus,
  command: Runes) =

    status.jumpToSymbol(command)
