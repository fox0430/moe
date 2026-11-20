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

## The keys of an open picker. Its mappings (`cmap`, as for Vim's input())
## have had the key. A key that reads the list first brings it up to the
## query, so keys typed or replayed ahead of the frame act on what was typed;
## the rest edit the query as the command line's keys do.

import std/[monotimes, options]

import ../[editor, types, key_bindings, prompt_line]
import ../picker/[session, render, layout]
import result_processor, handler_result

const PickerKeys = [
  (KeyCombo(isSpecial: true, special: skDown), paNext),
  (KeyCombo(isSpecial: false, char: "n", modifiers: {kmCtrl}), paNext),
  (KeyCombo(isSpecial: true, special: skUp), paPrevious),
  (KeyCombo(isSpecial: false, char: "p", modifiers: {kmCtrl}), paPrevious),
  (KeyCombo(isSpecial: true, special: skPageDown), paPageDown),
  (KeyCombo(isSpecial: true, special: skPageUp), paPageUp),
  (KeyCombo(isSpecial: false, char: "x", modifiers: {kmCtrl}), paSplit),
  (KeyCombo(isSpecial: false, char: "v", modifiers: {kmCtrl}), paVSplit),
  (KeyCombo(isSpecial: true, special: skDown, modifiers: {kmShift}), paPreviewDown),
  (KeyCombo(isSpecial: true, special: skUp, modifiers: {kmShift}), paPreviewUp),
]
  ## The keys a picker takes before its prompt does. Up and Down, Ctrl-P and
  ## Ctrl-N go through the list as in Vim's popup menu, not the history
  ## (Ctrl-Up and Ctrl-Down do that), and PageUp and PageDown page it.
  ## Shift-Down and Shift-Up scroll the preview, so only a picker with nothing
  ## to preview leaves them to the prompt's unfiltered history; a literal
  ## character is Ctrl-Q's.

proc pickerAction(key: KeyCombo, previews: bool): Option[PickerAction] =
  for (k, action) in PickerKeys:
    if not previews and action in {paPreviewDown, paPreviewUp}:
      continue
    let same =
      if not k.isSpecial and k.modifiers == {kmCtrl}:
        key.isCtrl(k.char[0])
      else:
        key == k
    if same:
      return some(action)
  none(PickerAction)

proc syncPicker(e: Editor) =
  e.state.picker.advancePicker(e.state.input.line.text)

proc screenLayout(e: Editor): PickerLayout =
  ## The picker on the screen as it last was.
  e.state.pickerScreenLayout(e.screenSize.width, e.screenSize.height)

proc listHeight(e: Editor): int =
  max(1, e.screenLayout.list.height)

proc scrollPreview(e: Editor, direction: int) =
  ## Scroll the preview half its height, as telescope does. With no room for
  ## the preview on the screen there is none to scroll.
  let height = e.screenLayout.preview.height
  if height > 0:
    e.scrollPickerPreview(direction * max(1, height div 2), getMonoTime())

proc closePicker(e: Editor) =
  ## Close the picker. A query typed at it goes into its history, opened or
  ## not, as one typed at Vim's input() does.
  let line = e.state.input.line
  if line.typed:
    e.state.input.pickerHistory.addToHistory(
      line.text, e.config.persist.commandHistoryLimit
    )
  e.state.exitOverlay(okPicker)
  e.setMode(e.state.mode)

proc confirmPicker(e: Editor, placement: ViewerPlacement): ReplayOutcome =
  ## Open the selected item from the window the picker was over, once it
  ## closed. With none to open, or a split of a command, it beeps and stays
  ## open.
  e.syncPicker()
  let item = e.state.picker.selectedItem
  if item.isNone or (placement != vpInPlace and item.get.target.kind == ptkExCommand):
    e.state.beep()
    return roContinue
  let origin = e.state.picker.origin
  e.closePicker()
  let queued = e.hostResultRequestCount
  let opens = HandlerResult(
    kind: hrPickerOpen,
    pickerTarget: item.get.target,
    pickerPlacement: placement,
    pickerOrigin: origin,
  )
  if not e.processResult(opens, e.activeBuffer):
    return roQuit
  if e.hostResultRequestCount > queued: roAbort else: roContinue

proc editPickerLine(e: Editor, key: KeyCombo) =
  ## Edit the query with `key`. Erasing on an empty one leaves the picker
  ## open, as Vim's input() with a prompt of its own.
  if e.state.editPrompt(e.activeBuffer, key, e.state.input.pickerHistory) == leBeep:
    e.state.beep()

proc runPickerAction(e: Editor, action: PickerAction): ReplayOutcome =
  e.syncPicker()
  let s = e.state.picker
  case action
  of paNext:
    s.moveSelection(1)
  of paPrevious:
    s.moveSelection(-1)
  of paPageDown:
    s.moveSelection(e.listHeight)
  of paPageUp:
    s.moveSelection(-e.listHeight)
  of paSplit:
    return e.confirmPicker(vpHSplit)
  of paVSplit:
    return e.confirmPicker(vpVSplit)
  of paPreviewDown:
    e.scrollPreview(1)
  of paPreviewUp:
    e.scrollPreview(-1)
  roContinue

proc handlePickerKeyCombo*(e: Editor, keyCombo: KeyCombo): ReplayOutcome =
  ## Run `keyCombo` on the open picker. Enter opens the selected item, and so
  ## does an Esc a mapping or a register puts in, as on the command line; a
  ## typed Esc and Ctrl-C close it.
  let key = e.state.input.line.takeKey(keyCombo, e.state.keyTyped, e.state.interrupted)
  if key == pkArgument:
    # What a Ctrl-R or a Ctrl-V waits for, whatever key it is.
    e.editPickerLine(keyCombo)
    return roContinue
  let action = pickerAction(keyCombo, e.state.picker.previews)
  if action.isSome:
    return e.runPickerAction(action.get)
  case key
  of pkEnter, pkRun:
    e.confirmPicker(vpInPlace)
  of pkLeave:
    e.closePicker()
    roContinue
  of pkOther, pkArgument:
    e.editPickerLine(keyCombo)
    roContinue
