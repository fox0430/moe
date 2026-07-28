#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## Call Hierarchy viewer state management
##
## This module provides the data structures and operations for the call hierarchy viewer mode.
## Used to display and navigate LSP call hierarchy results (incoming/outgoing calls).

import std/[strformat, options, os, strutils, tables]

import buffer/core, list_viewer, lsp_service, unicode_utils
import lsp/protocol/types as lspTypes
import types/callhierarchy_viewer_types

export callhierarchy_viewer_types
export list_viewer

proc newCallHierarchyViewerState*(
    items: seq[lspTypes.CallHierarchyItem], viewKind: CallHierarchyViewKind
): CallHierarchyViewerState =
  ## Create a new call hierarchy viewer state
  let title =
    case viewKind
    of chvkPrepare: "Call Hierarchy"
    of chvkIncoming: "Incoming Calls"
    of chvkOutgoing: "Outgoing Calls"
  CallHierarchyViewerState(
    items: items, selectedIndex: 0, viewKind: viewKind, title: title
  )

proc uriToPath(uri: string): string =
  ## Convert file:// URI to path
  lsp_service.uriToPath(uri)

proc formatLine*(item: lspTypes.CallHierarchyItem, lineText: string = ""): string =
  ## Format a call hierarchy item as a display line. `lineText` is the raw
  ## text of the target line, used to translate the LSP UTF-16 character
  ## offset into a rune-index column; pass "" to fall back to the raw offset.
  let path = uriToPath(item.uri)
  let detail =
    if item.detail.isSome:
      " " & item.detail.get
    else:
      ""
  let line = item.selectionRange.start.line + 1
  let col =
    if lineText.len > 0:
      utf16ToRuneIndex(lineText, item.selectionRange.start.character) + 1
    else:
      item.selectionRange.start.character + 1
  fmt"{item.name}{detail} ({path}:{line}:{col})"

proc createCallHierarchyTextBuffer*(state: CallHierarchyViewerState): TextBuffer =
  ## Create a TextBuffer from call hierarchy items for rendering via the normal view path
  let header = "-- " & state.title & " (" & $state.itemCount() & ") --"
  var fileCache = initTable[string, seq[string]]()
  proc formatItem(item: lspTypes.CallHierarchyItem): string =
    var lineText = ""
    if item.uri.startsWith("file://"):
      let path = uriToPath(item.uri)
      if not fileCache.hasKey(path):
        var lines: seq[string] = @[]
        if fileExists(path):
          try:
            lines = readFile(path).splitLines()
          except CatchableError:
            discard
        fileCache[path] = lines
      let lines = fileCache[path]
      let lineIdx = item.selectionRange.start.line
      if lineIdx >= 0 and lineIdx < lines.len:
        lineText = lines[lineIdx]
    formatLine(item, lineText)

  state.toListTextBuffer(header, formatItem)
