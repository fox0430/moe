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

## FileTree mode command handler
##
## This module handles commands specific to the NerdTree-style file tree sidebar.

import std/options

import ../[filetree, key_bindings]

type
  FileTreeResultKind* = enum
    ftrHandled # Command was handled
    ftrOpenFile # Open a file in the editor
    ftrEnterCommand # Enter command mode overlay
    ftrNextWindow # Switch to next window
    ftrPrevWindow # Switch to previous window
    ftrIncreaseWindowWidth # Increase active window width
    ftrDecreaseWindowWidth # Decrease active window width
    ftrUnhandled # Command was not handled
    ftrError # Error occurred

  FileTreeResult* = object
    statusMessage*: string # Status/command line text to display
    case kind*: FileTreeResultKind
    of ftrOpenFile:
      filePath*: string
    of ftrError:
      errorMessage*: string
    else:
      discard

  FileTreeHandler* = ref object
    waitingForG*: bool # Waiting for second 'g' for 'gg' command
    waitingForCtrlW*: bool # Waiting for second key after Ctrl-w
    isSearching*: bool # In search input mode
    searchBuffer*: string # Text being typed during search

proc newFileTreeHandler*(): FileTreeHandler =
  FileTreeHandler(
    waitingForG: false, waitingForCtrlW: false, isSearching: false, searchBuffer: ""
  )

proc handleFileTreeModeKey*(
    handler: FileTreeHandler,
    fileTreeState: FileTreeState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): FileTreeResult =
  ## Handle a key press in FileTree mode

  # Search input mode
  if handler.isSearching:
    if keyCombo.isSpecial:
      case keyCombo.special
      of skEscape:
        # Cancel search
        handler.isSearching = false
        handler.searchBuffer = ""
        fileTreeState.clearSearch()
        return FileTreeResult(kind: ftrHandled, statusMessage: "")
      of skEnter:
        # Confirm search
        handler.isSearching = false
        handler.searchBuffer = ""
        let msg =
          if fileTreeState.searchText.len > 0:
            "/" & fileTreeState.searchText
          else:
            ""
        return FileTreeResult(kind: ftrHandled, statusMessage: msg)
      of skBackspace:
        if handler.searchBuffer.len > 0:
          handler.searchBuffer.setLen(handler.searchBuffer.len - 1)
          fileTreeState.searchText = handler.searchBuffer
          fileTreeState.updateSearchMatches()
          if fileTreeState.searchMatches.len > 0:
            fileTreeState.jumpToFirstMatch(viewportHeight)
        return
          FileTreeResult(kind: ftrHandled, statusMessage: "/" & handler.searchBuffer)
      else:
        return
          FileTreeResult(kind: ftrHandled, statusMessage: "/" & handler.searchBuffer)
    else:
      # Normal character input
      handler.searchBuffer.add(keyCombo.char)
      fileTreeState.searchText = handler.searchBuffer
      fileTreeState.updateSearchMatches()
      if fileTreeState.searchMatches.len > 0:
        fileTreeState.jumpToFirstMatch(viewportHeight)
      return FileTreeResult(kind: ftrHandled, statusMessage: "/" & handler.searchBuffer)

  # Handle 'gg' command
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      fileTreeState.moveToFirst()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    # Non-g key cancels the pending g and falls through to handle it normally

  # Handle Ctrl-w + second key for window operations
  if handler.waitingForCtrlW:
    handler.waitingForCtrlW = false
    if not keyCombo.isSpecial:
      case keyCombo.char
      of ">":
        return FileTreeResult(kind: ftrIncreaseWindowWidth)
      of "<":
        return FileTreeResult(kind: ftrDecreaseWindowWidth)
      of "w":
        return FileTreeResult(kind: ftrNextWindow)
      of "p":
        return FileTreeResult(kind: ftrPrevWindow)
      else:
        return FileTreeResult(kind: ftrUnhandled)
    else:
      return FileTreeResult(kind: ftrUnhandled)

  # Escape does nothing
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return FileTreeResult(kind: ftrHandled)

  # Special keys
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      let node = fileTreeState.getSelectedNode()
      if node.isSome:
        if node.get.isDirectory:
          fileTreeState.toggleExpand()
          fileTreeState.ensureSelectedVisible(viewportHeight)
        else:
          return FileTreeResult(kind: ftrOpenFile, filePath: node.get.path)
      return FileTreeResult(kind: ftrHandled)
    of skUp:
      fileTreeState.moveUp()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of skDown:
      fileTreeState.moveDown()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    else:
      discard
  else:
    # Ctrl-w starts window command sequence
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "w":
      handler.waitingForCtrlW = true
      return FileTreeResult(kind: ftrHandled)

    case keyCombo.char
    of ":":
      return FileTreeResult(kind: ftrEnterCommand)
    of "/":
      # Start search
      handler.isSearching = true
      handler.searchBuffer = ""
      return FileTreeResult(kind: ftrHandled, statusMessage: "/")
    of "n":
      # Next search match
      fileTreeState.jumpToNextMatch(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of "N":
      # Previous search match
      fileTreeState.jumpToPrevMatch(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of "j":
      fileTreeState.moveDown()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of "k":
      fileTreeState.moveUp()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of "o":
      # Open file or toggle expand/collapse directory
      let node = fileTreeState.getSelectedNode()
      if node.isSome:
        if node.get.isDirectory:
          fileTreeState.toggleExpand()
          fileTreeState.ensureSelectedVisible(viewportHeight)
        else:
          return FileTreeResult(kind: ftrOpenFile, filePath: node.get.path)
      return FileTreeResult(kind: ftrHandled)
    of "l":
      # Open file or expand directory (expand only, no collapse)
      let node = fileTreeState.getSelectedNode()
      if node.isSome:
        if node.get.isDirectory:
          fileTreeState.expandSelected()
          fileTreeState.ensureSelectedVisible(viewportHeight)
        else:
          return FileTreeResult(kind: ftrOpenFile, filePath: node.get.path)
      return FileTreeResult(kind: ftrHandled)
    of "x", "h":
      # Collapse or move to parent
      fileTreeState.collapseSelected()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of "p":
      # Move to parent node
      if not fileTreeState.moveToParent():
        return FileTreeResult(
          kind: ftrError, errorMessage: "Parent directory not visible in tree"
        )
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of "C":
      # Change root to selected directory
      fileTreeState.changeRoot()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of "u":
      # Move root up one level
      fileTreeState.moveRootUp()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of ".":
      # Toggle hidden files
      fileTreeState.toggleHidden()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of "R":
      # Refresh tree
      fileTreeState.refreshTree()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    of "g":
      handler.waitingForG = true
      return FileTreeResult(kind: ftrHandled)
    of "G":
      fileTreeState.moveToLast()
      fileTreeState.ensureSelectedVisible(viewportHeight)
      return FileTreeResult(kind: ftrHandled)
    else:
      discard

  return FileTreeResult(kind: ftrUnhandled)
