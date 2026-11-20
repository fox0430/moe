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

## The items each source lists. A source collects them all when the picker
## opens, so a key typed right after `:picker` finds them there.

import std/[options, strutils, tables]

import pkg/results

import ../types/editor_types
import ../[types, buffer, persist, unicode_utils, display_path]

type PickerContents* = object
  title*: string
  items*: seq[PickerItem]
  message*: string ## Why there are no items, when it is not that none matched
  previews*: bool ## Whether the items name files or buffers to preview

proc item(prefix, name: string, target: PickerTarget): PickerItem =
  ## An item showing `name` after `prefix`, matched on `name`.
  let key = name.forDisplay
  PickerItem(key: key, display: prefix & key, keyAt: prefix.charLen, target: target)

proc bufferItems(e: Editor, current: BufferId): PickerContents =
  ## The buffers, as `:ls` lists them: the number, `%` for the window's own and
  ## `+` for a modified one, and the name.
  result.title = "Buffers"
  result.previews = true
  var width = 0
  for b in e.buffers:
    width = max(width, ($b.id.int).len)
  for b in e.buffers:
    let prefix =
      align($b.id.int, width) & " " & (if b.id == current: "%" else: " ") &
      (if b.isModified: "+" else: " ") & " "
    result.items.add item(
      prefix, b.canonicalLabel, PickerTarget(kind: ptkBuffer, buffer: b.id)
    )

proc oldfileItems(e: Editor): PickerContents =
  ## The files the cursor positions were saved for, the last edited first, as
  ## Vim's `:oldfiles`: what the file held when the picker opened, without the
  ## files of this session it has yet to save.
  result.title = "Old files"
  result.previews = true
  if not e.config.persist.cursorPosition:
    result.message = "Cursor positions are not saved ([Persist] cursorPosition)"
    return
  let records = loadCursorPositions()
  if records.isErr:
    result.message = records.error.forDisplay
    return
  for path in records.get.keys:
    result.items.add item("", path.homeReplace, PickerTarget(kind: ptkFile, path: path))

proc sourceItems(): PickerContents =
  result.title = "Pickers"
  var width = 0
  for source in PickerSourceKind:
    width = max(width, ($source).len)
  for source in PickerSourceKind:
    var it =
      item("", $source, PickerTarget(kind: ptkExCommand, command: "picker " & $source))
    it.display = alignLeft($source, width) & "  " & PickerSourceDescriptions[source]
    result.items.add it

proc collectPickerItems*(e: Editor, spec: PickerSpec): PickerContents =
  ## What `spec`'s source lists for the active window.
  if spec.source.isNone:
    return sourceItems()
  case spec.source.get
  of psBuffers:
    e.bufferItems(e.tabBuffer(e.activeWindow).id)
  of psOldfiles:
    e.oldfileItems()
