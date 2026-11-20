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

## `:picker`, which opens a picker over the active window, and the opening of
## what an item names once the picker closed.

import std/options

import pkg/results

import
  ../[
    editor, types, editor_open, editor_window, editor_codelens, hover_popup, viewer_mode
  ]
import ../picker/sources
import handler_result

proc processPickerEnter*(e: Editor, r: HandlerResult): bool =
  ## Open the picker `r` asks for, its source's items collected now so a key
  ## typed right after finds them. A resume takes the last one back as it
  ## was left, over the window it is run in.
  let spec = r.pickerSpec
  if spec.resume:
    if not e.state.resumePickerOverlay(e.activeWindow):
      e.state.statusMessage = "No picker to resume"
      e.state.beep()
      return true
    # A buffer may hold the selected item's file now, and with no selection
    # the last subject would stay.
    e.state.picker.preview.item = none(int)
    e.state.picker.preview.subject = PreviewSubject(kind: pvNone)
  else:
    let contents = e.collectPickerItems(spec)
    let session = PickerSession(
      title: contents.title,
      items: contents.items,
      message: contents.message,
      previews: contents.previews,
    )
    e.state.enterPickerOverlay(session, spec.query.get(""), e.activeWindow)
  # The picker covers the window the popups belong to.
  e.state.lspCache.hoverPopup.hide()
  e.state.lspCache.hideCodeLensPicker()
  e.state.ui.tempMessages = @[]
  true

proc processPickerOpen*(e: Editor, r: HandlerResult, subject: JumpSubject): bool =
  ## Open `subject`, which `r`'s item names, from the window the picker was
  ## over, or the active one if that went. A viewer over the window goes
  ## first, as for a jump from it. A failure beeps, so a register or a mapping
  ## running the keys stops.
  # A buffer gone since the list was made fails before the viewer goes, as
  # Vim's `:b` of one leaves all as it was.
  if subject.isBuffer and e.bufferIndexById(subject.id) < 0:
    e.state.statusMessage = "Buffer no longer available"
    e.state.beep()
    return true
  let origin = e.windowManager.windows.find(r.pickerOrigin)
  if origin >= 0:
    e.focusWindow(origin)
  if e.activeWindow.viewerEntry.isSome:
    discard e.leaveViewerModeForJump(e.activeWindow.mode)
  let opened = e.jumpTo(subject, none(TargetPosition), r.pickerPlacement)
  if opened.isErr:
    e.state.statusMessage = opened.error
    e.state.beep()
  true
