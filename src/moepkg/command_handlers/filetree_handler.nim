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
import handler_types
export handler_types

type
  FileTreeResultKind* = enum
    ftrHandled # Command was handled
    ftrOpenFile # Open a file in the editor
    ftrEnterCommand # Enter command mode overlay
    ftrNextWindow # Switch to next window
    ftrPrevWindow # Switch to previous window
    ftrIncreaseWindowWidth # Increase active window width
    ftrDecreaseWindowWidth # Decrease active window width
    ftrClearSearchHighlight # Clear the persisted search highlight
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

proc handleFileTreeModeKey*(
    fileTreeState: FileTreeState, viewportHeight: int, keyCombo: KeyCombo
): FileTreeResult =
  ## Handle a key press in FileTree mode

  # Search input mode
  if fileTreeState.isSearching:
    if keyCombo.isSpecial:
      case keyCombo.special
      of skEscape:
        # Cancel search
        fileTreeState.isSearching = false
        fileTreeState.clearSearch()
        return FileTreeResult(kind: ftrHandled, statusMessage: "")
      of skEnter:
        # Confirm search (keep searchText so the match highlight persists)
        fileTreeState.isSearching = false
        let msg =
          if fileTreeState.searchText.len > 0:
            "/" & fileTreeState.searchText
          else:
            ""
        return FileTreeResult(kind: ftrHandled, statusMessage: msg)
      of skBackspace:
        if fileTreeState.searchText.len > 0:
          fileTreeState.searchText.setLen(fileTreeState.searchText.len - 1)
          fileTreeState.updateSearchMatches()
          if fileTreeState.searchMatches.len > 0:
            fileTreeState.jumpToFirstMatch()
        return FileTreeResult(
          kind: ftrHandled, statusMessage: "/" & fileTreeState.searchText
        )
      else:
        return FileTreeResult(
          kind: ftrHandled, statusMessage: "/" & fileTreeState.searchText
        )
    else:
      # Normal character input
      fileTreeState.searchText.add(keyCombo.char)
      fileTreeState.updateSearchMatches()
      if fileTreeState.searchMatches.len > 0:
        fileTreeState.jumpToFirstMatch()
      return
        FileTreeResult(kind: ftrHandled, statusMessage: "/" & fileTreeState.searchText)

  # Handle 'gg' command
  if fileTreeState.waitingForG:
    fileTreeState.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      fileTreeState.moveToFirst()
      return FileTreeResult(kind: ftrHandled)
    # Non-g key cancels the pending g and falls through to handle it normally

  # Handle Ctrl-w + second key for window operations
  if fileTreeState.waitingForCtrlW:
    fileTreeState.waitingForCtrlW = false
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

  # Double-Escape clears the search highlight (single Escape just arms it).
  # The handler only reports the intent; the dispatcher performs the clear,
  # mirroring the Config/Help handlers.
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    if fileTreeState.lastKeyWasEscape:
      fileTreeState.lastKeyWasEscape = false
      return FileTreeResult(kind: ftrClearSearchHighlight, statusMessage: "")
    else:
      fileTreeState.lastKeyWasEscape = true
      return FileTreeResult(kind: ftrHandled)

  # Any non-Escape key resets the Escape counter
  fileTreeState.lastKeyWasEscape = false

  # Special keys
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      let node = fileTreeState.getSelectedNode()
      if node.isSome:
        if node.get.isDirectory:
          fileTreeState.toggleExpand()
        else:
          return FileTreeResult(kind: ftrOpenFile, filePath: node.get.path)
      return FileTreeResult(kind: ftrHandled)
    of skUp:
      fileTreeState.moveUp()
      return FileTreeResult(kind: ftrHandled)
    of skDown:
      fileTreeState.moveDown()
      return FileTreeResult(kind: ftrHandled)
    else:
      discard
  else:
    # Ctrl-w starts window command sequence
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "w":
      fileTreeState.waitingForCtrlW = true
      return FileTreeResult(kind: ftrHandled)

    case keyCombo.char
    of ":":
      return FileTreeResult(kind: ftrEnterCommand)
    of "/":
      # Start search (clear searchText so typed input does not append to the old word)
      fileTreeState.isSearching = true
      fileTreeState.searchText = ""
      return FileTreeResult(kind: ftrHandled, statusMessage: "/")
    of "n":
      # Next search match
      fileTreeState.jumpToNextMatch()
      return FileTreeResult(kind: ftrHandled)
    of "N":
      # Previous search match
      fileTreeState.jumpToPrevMatch()
      return FileTreeResult(kind: ftrHandled)
    of "j":
      fileTreeState.moveDown()
      return FileTreeResult(kind: ftrHandled)
    of "k":
      fileTreeState.moveUp()
      return FileTreeResult(kind: ftrHandled)
    of "o":
      # Open file or toggle expand/collapse directory
      let node = fileTreeState.getSelectedNode()
      if node.isSome:
        if node.get.isDirectory:
          fileTreeState.toggleExpand()
        else:
          return FileTreeResult(kind: ftrOpenFile, filePath: node.get.path)
      return FileTreeResult(kind: ftrHandled)
    of "l":
      # Open file or expand directory (expand only, no collapse)
      let node = fileTreeState.getSelectedNode()
      if node.isSome:
        if node.get.isDirectory:
          fileTreeState.expandSelected()
        else:
          return FileTreeResult(kind: ftrOpenFile, filePath: node.get.path)
      return FileTreeResult(kind: ftrHandled)
    of "x", "h":
      # Collapse or move to parent
      fileTreeState.collapseSelected()
      return FileTreeResult(kind: ftrHandled)
    of "p":
      # Move to parent node
      if not fileTreeState.moveToParent():
        return FileTreeResult(
          kind: ftrError, errorMessage: "Parent directory not visible in tree"
        )
      return FileTreeResult(kind: ftrHandled)
    of "C":
      # Change root to selected directory
      fileTreeState.changeRoot()
      return FileTreeResult(kind: ftrHandled)
    of "u":
      # Move root up one level
      fileTreeState.moveRootUp()
      return FileTreeResult(kind: ftrHandled)
    of ".":
      # Toggle hidden files
      fileTreeState.toggleHidden()
      return FileTreeResult(kind: ftrHandled)
    of "R":
      # Refresh tree
      fileTreeState.refreshTree()
      return FileTreeResult(kind: ftrHandled)
    of "g":
      fileTreeState.waitingForG = true
      return FileTreeResult(kind: ftrHandled)
    of "G":
      fileTreeState.moveToLast()
      return FileTreeResult(kind: ftrHandled)
    else:
      discard

  return FileTreeResult(kind: ftrUnhandled)
