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

## Sidebar management for editor windows
##
## This module provides functionality for managing and updating the sidebar
## displayed on the left side of editor windows. The sidebar shows:
## - Git diff indicators (added, changed, deleted lines)
## - Syntax checker results (errors, warnings)

import std/[options, unicode]

import pkg/celina

import types, buffer, color

# Sidebar display constants
const DefaultSidebarWidth* = 2

# Marker configuration type
type SidebarMarkerConfig* = object ## Configuration for sidebar marker display strings
  gitAdded*: string
  gitChanged*: string
  gitDeleted*: string
  gitChangedAndDeleted*: string
  gitConflict*: string
  syntaxError*: string
  syntaxWarning*: string
  sessionModified*: string
  sessionInserted*: string
  bookmark*: string

# Default marker values
const
  DefaultGitAddedMarker = "+ "
  DefaultGitChangedMarker = "~ "
  DefaultGitDeletedMarker = "_ "
  DefaultGitChangedAndDeletedMarker = "~_"
  DefaultGitConflictMarker = "!!"
  DefaultSyntaxErrorMarker = ">>"
  DefaultSyntaxWarningMarker = "⚠ "
  DefaultSessionModifiedMarker = "~ "
  DefaultSessionInsertedMarker = "+ "
  DefaultBookmarkMarker = "♥ "

# Global marker configuration (can be customized via settings in the future)
var globalMarkerConfig* = SidebarMarkerConfig(
  gitAdded: DefaultGitAddedMarker,
  gitChanged: DefaultGitChangedMarker,
  gitDeleted: DefaultGitDeletedMarker,
  gitChangedAndDeleted: DefaultGitChangedAndDeletedMarker,
  gitConflict: DefaultGitConflictMarker,
  syntaxError: DefaultSyntaxErrorMarker,
  syntaxWarning: DefaultSyntaxWarningMarker,
  sessionModified: DefaultSessionModifiedMarker,
  sessionInserted: DefaultSessionInsertedMarker,
  bookmark: DefaultBookmarkMarker,
)

proc setBookmarkMarker*(marker: string) =
  ## Set the bookmark marker display string
  globalMarkerConfig.bookmark = marker

# Helper to get theme background color
proc themeBackground(): ColorValue =
  let colorPair = getThemeColor(EditorColorPairIndex.default)
  colorPair.background.rgb.toColorValue

# Style getter procs for different sidebar indicators (colors come from the theme)
proc gitAddedStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.sidebarGitAddedSign)

proc gitChangedStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.sidebarGitChangedSign)

proc gitDeletedStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.sidebarGitDeletedSign)

proc gitConflictSidebarStyle*(): Style =
  var style = getThemeStyle(EditorColorPairIndex.sidebarGitConflictSign)
  style.modifiers.incl(StyleModifier.Bold)
  style

proc syntaxErrorStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.sidebarSyntaxCheckErrSign, {StyleModifier.Bold})

proc syntaxWarningStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.sidebarSyntaxCheckWarnSign)

proc sessionModifiedStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.sidebarSessionModifiedSign)

proc sessionInsertedStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.sidebarSessionInsertedSign)

proc bookmarkStyle*(): Style =
  getThemeStyle(EditorColorPairIndex.sidebarBookmarkSign, {StyleModifier.Bold})

proc emptyStyle*(): Style =
  Style(fg: ColorValue(kind: Default), bg: themeBackground(), modifiers: {})

proc getStyleForKind(kind: LineMarkerKind): Style =
  ## Get the appropriate style for a sidebar item kind
  case kind
  of GitAdded:
    gitAddedStyle()
  of GitChanged:
    gitChangedStyle()
  of GitDeleted:
    gitDeletedStyle()
  of GitChangedAndDeleted:
    gitChangedStyle()
  of GitConflict:
    gitConflictSidebarStyle()
  of SyntaxError:
    syntaxErrorStyle()
  of SyntaxWarning:
    syntaxWarningStyle()
  of SessionModified:
    sessionModifiedStyle()
  of SessionInserted:
    sessionInsertedStyle()
  of Bookmark:
    bookmarkStyle()

proc emptySidebarItem(): SidebarItem =
  ## Create an empty sidebar item
  SidebarItem(text: " ", kind: none(LineMarkerKind), style: emptyStyle())

proc initSidebar*(height: int, width: int = DefaultSidebarWidth): Sidebar =
  ## Initialize a new sidebar with the given dimensions
  result.width = width
  result.buffer = newSeq[seq[SidebarItem]](height)
  for y in 0 ..< height:
    result.buffer[y] = newSeq[SidebarItem](width)
    for x in 0 ..< width:
      result.buffer[y][x] = emptySidebarItem()

proc clearSidebar*(sidebar: var Sidebar) =
  ## Clear all sidebar content (set all cells to empty)
  for y in 0 ..< sidebar.buffer.len:
    for x in 0 ..< sidebar.width:
      sidebar.buffer[y][x] = emptySidebarItem()

proc resizeSidebar*(sidebar: var Sidebar, newHeight: int) =
  ## Resize sidebar to new height, preserving existing content where possible
  let oldHeight = sidebar.buffer.len

  if newHeight > oldHeight:
    # Add new empty lines
    for y in oldHeight ..< newHeight:
      var newLine = newSeq[SidebarItem](sidebar.width)
      for x in 0 ..< sidebar.width:
        newLine[x] = emptySidebarItem()
      sidebar.buffer.add(newLine)
  elif newHeight < oldHeight:
    # Remove excess lines
    sidebar.buffer.setLen(newHeight)

proc setSidebarItem*(
    sidebar: var Sidebar, line: int, col: int, text: string, kind: LineMarkerKind
) =
  ## Set a single sidebar cell
  if line >= 0 and line < sidebar.buffer.len and col >= 0 and col < sidebar.width:
    let style = getStyleForKind(kind)
    sidebar.buffer[line][col] = SidebarItem(text: text, kind: some(kind), style: style)

proc setSidebarLine*(
    sidebar: var Sidebar, line: int, text: string, kind: LineMarkerKind
) =
  ## Set an entire sidebar line with the same indicator.
  ## Width-2 runes claim two cells (base + empty shadow) to stay compatible
  ## with celina's wide-char cell model.
  if line < 0 or line >= sidebar.buffer.len:
    return

  let style = getStyleForKind(kind)
  var col = 0

  for rune in text.runes:
    if col >= sidebar.width:
      break
    let w = runeWidth(rune)
    if w == 0:
      if col > 0:
        sidebar.buffer[line][col - 1].text.add($rune)
      continue
    if w == 2:
      if col + 1 >= sidebar.width:
        break
      sidebar.buffer[line][col] =
        SidebarItem(text: $rune, kind: some(kind), style: style)
      sidebar.buffer[line][col + 1] =
        SidebarItem(text: "", kind: some(kind), style: style)
      col += 2
    else:
      sidebar.buffer[line][col] =
        SidebarItem(text: $rune, kind: some(kind), style: style)
      inc col

  while col < sidebar.width:
    sidebar.buffer[line][col] = SidebarItem(text: " ", kind: some(kind), style: style)
    inc col

proc clearSidebarLine*(sidebar: var Sidebar, line: int) =
  ## Clear a single sidebar line (set to empty)
  if line >= 0 and line < sidebar.buffer.len:
    for col in 0 ..< sidebar.width:
      sidebar.buffer[line][col] = emptySidebarItem()

# Git diff integration (placeholder for future implementation)
# These functions will be connected to the git diff system when available

proc updateSidebarForGitAdded*(sidebar: var Sidebar, lineNumber: int) =
  ## Mark a line as added in git diff
  setSidebarLine(sidebar, lineNumber, globalMarkerConfig.gitAdded, GitAdded)

proc updateSidebarForGitChanged*(sidebar: var Sidebar, lineNumber: int) =
  ## Mark a line as changed in git diff
  setSidebarLine(sidebar, lineNumber, globalMarkerConfig.gitChanged, GitChanged)

proc updateSidebarForGitDeleted*(sidebar: var Sidebar, lineNumber: int) =
  ## Mark a line as deleted in git diff
  setSidebarLine(sidebar, lineNumber, globalMarkerConfig.gitDeleted, GitDeleted)

proc updateSidebarForGitChangedAndDeleted*(sidebar: var Sidebar, lineNumber: int) =
  ## Mark a line as changed and deleted in git diff
  setSidebarLine(
    sidebar, lineNumber, globalMarkerConfig.gitChangedAndDeleted, GitChangedAndDeleted
  )

# Syntax checker integration (placeholder for future implementation)
# These functions will be connected to the LSP/syntax checker system when available

proc updateSidebarForSyntaxError*(sidebar: var Sidebar, lineNumber: int) =
  ## Mark a line with a syntax error
  setSidebarLine(sidebar, lineNumber, globalMarkerConfig.syntaxError, SyntaxError)

proc updateSidebarForSyntaxWarning*(sidebar: var Sidebar, lineNumber: int) =
  ## Mark a line with a syntax warning
  setSidebarLine(sidebar, lineNumber, globalMarkerConfig.syntaxWarning, SyntaxWarning)

proc generateSidebarFromBuffer*(
    b: TextBuffer,
    topLine: int,
    height: int,
    width: int = DefaultSidebarWidth,
    modifiedLines: seq[LineModificationKind] = @[],
    showModifiedLines: bool = false,
    bookmarks: seq[int] = @[],
): Sidebar =
  ## Generate a sidebar view from buffer markers for the visible range.
  ## If showModifiedLines is true, lines with no other marker but modified/inserted in
  ## the current session will show a SessionModified/SessionInserted indicator as fallback.
  ## Bookmarks are shown when no SyntaxError/SyntaxWarning marker is present.
  result = initSidebar(height, width)

  # Map buffer markers to sidebar for visible range
  for screenLine in 0 ..< height:
    let bufferLine = topLine + screenLine
    if bufferLine >= 0 and bufferLine < b.len:
      let marker = b.getLineMarker(bufferLine)
      if marker.isSome:
        let kind = marker.get
        if kind in {SyntaxError, SyntaxWarning}:
          # SyntaxError/Warning take highest priority
          let text =
            case kind
            of SyntaxError: globalMarkerConfig.syntaxError
            of SyntaxWarning: globalMarkerConfig.syntaxWarning
            else: " "
          setSidebarLine(result, screenLine, text, kind)
        elif kind == GitConflict:
          # GitConflict outranks bookmarks and regular git markers — a merge
          # conflict is actionable state the user needs to resolve first.
          setSidebarLine(
            result, screenLine, globalMarkerConfig.gitConflict, GitConflict
          )
        elif b.hasBookmark(bufferLine):
          # Bookmark overrides git/session markers
          setSidebarLine(result, screenLine, globalMarkerConfig.bookmark, Bookmark)
        else:
          # Generate appropriate text for this marker kind from configuration
          let text =
            case kind
            of GitAdded: globalMarkerConfig.gitAdded
            of GitChanged: globalMarkerConfig.gitChanged
            of GitDeleted: globalMarkerConfig.gitDeleted
            of GitChangedAndDeleted: globalMarkerConfig.gitChangedAndDeleted
            of GitConflict: globalMarkerConfig.gitConflict
            of SyntaxError: globalMarkerConfig.syntaxError
            of SyntaxWarning: globalMarkerConfig.syntaxWarning
            of SessionModified: globalMarkerConfig.sessionModified
            of SessionInserted: globalMarkerConfig.sessionInserted
            of Bookmark: globalMarkerConfig.bookmark
          setSidebarLine(result, screenLine, text, kind)
      elif b.hasBookmark(bufferLine):
        # No marker but has bookmark
        setSidebarLine(result, screenLine, globalMarkerConfig.bookmark, Bookmark)
      elif showModifiedLines and bufferLine < modifiedLines.len:
        # Fallback: show session marker when no other marker exists
        case modifiedLines[bufferLine]
        of lmkModified:
          setSidebarLine(
            result, screenLine, globalMarkerConfig.sessionModified, SessionModified
          )
        of lmkInserted:
          setSidebarLine(
            result, screenLine, globalMarkerConfig.sessionInserted, SessionInserted
          )
        of lmkUnmodified:
          discard
