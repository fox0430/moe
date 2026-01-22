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

## Tab line rendering for moe editor
##
## This module provides VSCode-like tab line functionality, displaying
## open buffers as tabs at the top of each window.

import std/[options, os, strutils]

import pkg/celina

import types, buffer, color, unicode_utils

proc toggleTabLine*(state: var EditorState) =
  ## Toggle the visibility of the tab line
  state.display.showTabLine = not state.display.showTabLine

proc setTabLineVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of the tab line
  state.display.showTabLine = visible

proc getTabStyle(): Style =
  ## Get the tab style from theme
  getThemeStyle(EditorColorPairIndex.tab, {StyleModifier.Bold})

proc getCurrentTabStyle(): Style =
  ## Get the current (active) tab style from theme
  getThemeStyle(EditorColorPairIndex.currentTab)

proc buildTabText(buf: TextBuffer): string =
  ## Build the display text for a single tab
  ## Format: " filename[+] " where [+] indicates modified
  let
    name = if buf.filePath.isSome: buf.filePath.get.extractFilename else: "No Name"
    modMark = if buf.isModified: "[+]" else: ""

  result = " " & name & modMark & " "

proc renderTabLine*(
    buffers: seq[TextBuffer],
    activeBuffer: TextBuffer,
    displayBuffer: var Buffer,
    tabLineY: int,
    tabLineX: int,
    tabLineWidth: int,
    showTabLine: bool,
) =
  ## Render the tab line showing all open buffers
  ##
  ## Parameters:
  ## - buffers: List of all open buffers to display as tabs
  ## - activeBuffer: The currently active buffer (will be highlighted)
  ## - displayBuffer: The screen buffer to render to
  ## - tabLineY: Y coordinate for the tab line
  ## - tabLineX: X coordinate for the start of the tab line
  ## - tabLineWidth: Width of the tab line area
  ## - showTabLine: Whether the tab line should be shown

  if not showTabLine:
    return

  let
    tabStyle = getTabStyle()
    currentTabStyle = getCurrentTabStyle()

  # Follow statusline pattern: render content first, then fill remaining space
  var currentX = tabLineX

  # First, render all tabs (visible content)
  for buf in buffers:
    let
      isActive = (buf.id == activeBuffer.id)
      style = if isActive: currentTabStyle else: tabStyle
      tabText = buildTabText(buf)
      tabWidth = displayWidth(tabText)

    # Stop if we would exceed the tab line width
    if currentX + tabWidth > tabLineX + tabLineWidth:
      break

    # Draw the tab
    displayBuffer.setString(currentX, tabLineY, tabText, style)
    currentX += tabWidth

  # Then fill the remaining space with background (like statusline does)
  let remainingWidth = max(0, tabLineX + tabLineWidth - currentX)
  if remainingWidth > 0:
    let background = " ".repeat(remainingWidth)
    displayBuffer.setString(currentX, tabLineY, background, tabStyle)

proc renderWindowTabLine*(
    buffers: seq[TextBuffer],
    windowActiveBuffer: TextBuffer,
    displayBuffer: var Buffer,
    windowY: int,
    windowX: int,
    windowWidth: int,
    showTabLine: bool,
) =
  ## Render tab line for a specific window (split view)
  ## The window's buffer will be highlighted as active
  ##
  ## Parameters:
  ## - buffers: List of all open buffers to display as tabs
  ## - windowActiveBuffer: The buffer displayed in this window (will be highlighted)
  ## - displayBuffer: The screen buffer to render to
  ## - windowY: Y coordinate of the window (tab line will be at this position)
  ## - windowX: X coordinate of the window
  ## - windowWidth: Width of the window
  ## - showTabLine: Whether the tab line should be shown

  renderTabLine(
    buffers, windowActiveBuffer, displayBuffer, windowY, windowX, windowWidth,
    showTabLine,
  )

proc renderSingleViewTabLine*(
    buffers: seq[TextBuffer],
    activeBuffer: TextBuffer,
    displayBuffer: var Buffer,
    showTabLine: bool,
) =
  ## Render tab line for single view mode
  ## Renders at y=0 across the full width
  ##
  ## Parameters:
  ## - buffers: List of all open buffers to display as tabs
  ## - activeBuffer: The currently active buffer (will be highlighted)
  ## - displayBuffer: The screen buffer to render to
  ## - showTabLine: Whether the tab line should be shown

  renderTabLine(
    buffers, activeBuffer, displayBuffer, displayBuffer.area.y, displayBuffer.area.x,
    displayBuffer.area.width, showTabLine,
  )
