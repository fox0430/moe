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

## Filer mode command handler
##
## This module handles commands specific to Filer (file explorer) mode.

import std/options

import ../[filer, key_bindings]
import handler_types
export handler_types

type
  FilerResultKind* = enum
    frHandled # Command was handled successfully
    frOpenFile # Open a file in the editor
    frOpenFileVSplit # Open file in vertical split
    frOpenFileHSplit # Open file in horizontal split
    frOpenDirectory # Navigate to a directory
    frEnterCommand # Enter command mode
    frDeleteFile # Delete selected file/directory
    frShowInfo # Show file information
    frUnhandled # Command was not handled
    frError # Error occurred

  FilerResult* = object
    case kind*: FilerResultKind
    of frOpenFile, frOpenFileVSplit, frOpenFileHSplit:
      filePath*: string
    of frOpenDirectory:
      dirPath*: string
    of frDeleteFile:
      deletePath*: string
    of frShowInfo:
      fileInfo*: string
    of frError:
      errorMessage*: string
    else:
      discard

proc handleFilerModeKey*(
    filerState: FilerState, viewportHeight: int, keyCombo: KeyCombo
): FilerResult =
  ## Handle a key press in Filer mode
  ##
  ## Returns a FilerResult indicating what action should be taken

  # Handle 'gg' command (two g presses)
  if filerState.waitingForG:
    filerState.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      filerState.moveToFirst()
      return FilerResult(kind: frHandled)
    # If not 'g', fall through to normal handling

  # Escape key does nothing in Filer mode (use 'q' to quit)
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return FilerResult(kind: frHandled)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      # Enter directory or open file (follows symlinks)
      let selectedPath = filerState.getSelectedPath()
      if selectedPath.isSome:
        let entry = filerState.getSelectedEntry()
        if entry.isSome:
          if entry.get.isDirectory:
            return FilerResult(kind: frOpenDirectory, dirPath: selectedPath.get)
          else:
            return FilerResult(kind: frOpenFile, filePath: selectedPath.get)
      return FilerResult(kind: frHandled)
    of skUp:
      filerState.moveUp()
      return FilerResult(kind: frHandled)
    of skDown:
      filerState.moveDown()
      return FilerResult(kind: frHandled)
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      filerState.halfPageDown(viewportHeight)
      return FilerResult(kind: frHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      filerState.halfPageUp(viewportHeight)
      return FilerResult(kind: frHandled)

    case keyCombo.char
    of ":":
      return FilerResult(kind: frEnterCommand)
    of "j":
      filerState.moveDown()
      return FilerResult(kind: frHandled)
    of "k":
      filerState.moveUp()
      return FilerResult(kind: frHandled)
    of "l":
      # Enter directory or open file (follows symlinks)
      let selectedPath = filerState.getSelectedPath()
      if selectedPath.isSome:
        let entry = filerState.getSelectedEntry()
        if entry.isSome:
          if entry.get.isDirectory:
            return FilerResult(kind: frOpenDirectory, dirPath: selectedPath.get)
          else:
            return FilerResult(kind: frOpenFile, filePath: selectedPath.get)
      return FilerResult(kind: frHandled)
    of "g":
      # Start waiting for second 'g'
      filerState.waitingForG = true
      return FilerResult(kind: frHandled)
    of "G":
      filerState.moveToLast()
      return FilerResult(kind: frHandled)
    of ".":
      filerState.toggleHidden()
      return FilerResult(kind: frHandled)
    of "v":
      # Vertical split (follows symlinks to files)
      let selectedPath = filerState.getSelectedPath()
      if selectedPath.isSome:
        let entry = filerState.getSelectedEntry()
        if entry.isSome and entry.get.isFile:
          return FilerResult(kind: frOpenFileVSplit, filePath: selectedPath.get)
      return FilerResult(kind: frHandled)
    of "h":
      # Horizontal split (follows symlinks to files)
      let selectedPath = filerState.getSelectedPath()
      if selectedPath.isSome:
        let entry = filerState.getSelectedEntry()
        if entry.isSome and entry.get.isFile:
          return FilerResult(kind: frOpenFileHSplit, filePath: selectedPath.get)
      return FilerResult(kind: frHandled)
    of "D":
      # Delete selected file or directory
      let selectedPath = filerState.getSelectedPath()
      if selectedPath.isSome:
        let entry = filerState.getSelectedEntry()
        if entry.isSome and entry.get.name != "..":
          return FilerResult(kind: frDeleteFile, deletePath: selectedPath.get)
      return FilerResult(kind: frHandled)
    of "i":
      # Show file information
      let info = filerState.getSelectedInfo()
      return FilerResult(kind: frShowInfo, fileInfo: info)
    else:
      discard

  return FilerResult(kind: frUnhandled)
