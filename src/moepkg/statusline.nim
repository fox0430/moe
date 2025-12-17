#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[strformat, options, strutils]

import pkg/celina

import types, buffer, modes

proc toggleStatusLine*(state: var EditorState) =
  ## Toggle the visibility of the status line
  state.display.showStatusLine = not state.display.showStatusLine

proc setStatusLineVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of the status line
  state.display.showStatusLine = visible

proc toggleLineCount*(state: var EditorState) =
  ## Toggle the visibility of line count in status line
  state.display.showLineCount = not state.display.showLineCount

proc setLineCountVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of line count in status line
  state.display.showLineCount = visible

proc toggleLinePercentage*(state: var EditorState) =
  ## Toggle the visibility of line percentage in status line
  state.display.showLinePercentage = not state.display.showLinePercentage

proc setLinePercentageVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of line percentage in status line
  state.display.showLinePercentage = visible

proc toggleEncoding*(state: var EditorState) =
  ## Toggle the visibility of encoding in status line
  state.display.showEncoding = not state.display.showEncoding

proc setEncodingVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of encoding in status line
  state.display.showEncoding = visible

proc toggleMultiStatusLine*(state: var EditorState) =
  ## Toggle between single status line (at bottom) and multi status lines (per window)
  state.display.multiStatusLine = not state.display.multiStatusLine

proc setMultiStatusLine*(state: var EditorState, enabled: bool) =
  ## Set multi status line mode
  state.display.multiStatusLine = enabled

proc renderStatusLine*(
    state: EditorState, textBuffer: TextBuffer, buffer: var Buffer, statusLineY: int
) =
  ## Render the status line at the specified Y position
  if not state.display.showStatusLine:
    return

  let
    modeLabel = modeLabel(state.mode)
    modeLabelStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.Black),
      bg: ColorValue(kind: Indexed, indexed: Color.White),
      modifiers: {StyleModifier.Bold},
    )
    statusLineStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.White),
      bg: ColorValue(kind: Indexed, indexed: Color.Blue),
      modifiers: {StyleModifier.Bold},
    )

  # Draw mode label with white background
  let
    modeLabelText = fmt" {modeLabel} "
    filePathText =
      if textBuffer.filePath.isSome:
        " " & textBuffer.filePath.get()
      else:
        " [No Name]"
    statusLeftText = modeLabelText & filePathText

  buffer.setString(buffer.area.x, statusLineY, modeLabelText, modeLabelStyle)
  buffer.setString(
    buffer.area.x + modeLabelText.len, statusLineY, filePathText, statusLineStyle
  )

  # Prepare line count and percentage display based on individual settings
  let
    lineCountText = block:
      var parts: seq[string] = @[]

      if state.display.showEncoding:
        parts.add(encodingToString(textBuffer.encoding))

      if state.display.showLinePercentage:
        let
          currentLine = state.cursor.line + 1 # Convert to 1-based
          totalLines = textBuffer.len
          percentage =
            if totalLines > 0:
              int((currentLine.float / totalLines.float) * 100.0)
            else:
              0
        parts.add(fmt"{percentage}%")

      if state.display.showLineCount:
        let
          currentLine = state.cursor.line + 1 # Convert to 1-based
          totalLines = textBuffer.len
        parts.add(fmt"{currentLine}/{totalLines}")

      if parts.len > 0:
        " " & parts.join(" ")
      else:
        ""
    lineCountWidth = lineCountText.len

  # Fill the rest of the line with blue background (full width)
  let remainingWidth = max(0, buffer.area.width - statusLeftText.len)
  if remainingWidth > 0:
    let blueBackground = " ".repeat(remainingWidth)
    buffer.setString(
      buffer.area.x + statusLeftText.len, statusLineY, blueBackground, statusLineStyle
    )

  # Draw encoding/line count/percentage with 1 character space from the right end if enabled and there's enough space
  if (
    state.display.showEncoding or state.display.showLineCount or
    state.display.showLinePercentage
  ) and lineCountText.len > 0 and buffer.area.width >= lineCountWidth + 1:
    buffer.setString(
      buffer.area.x + buffer.area.width - lineCountWidth - 1,
      statusLineY,
      lineCountText,
      statusLineStyle,
    )

proc renderWindowStatusLine*(
    state: EditorState,
    textBuffer: TextBuffer,
    buffer: var Buffer,
    statusLineY: int,
    statusLineX: int,
    statusLineWidth: int,
    isActiveWindow: bool,
) =
  ## Render a status line for a specific window
  if not state.display.showStatusLine or not state.display.multiStatusLine:
    return

  let
    modeLabel =
      if isActiveWindow:
        modeLabel(state.mode)
      else:
        ""
    modeLabelStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.Black),
      bg: ColorValue(kind: Indexed, indexed: Color.White),
      modifiers: {StyleModifier.Bold},
    )
    statusLineStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.White),
      bg: ColorValue(kind: Indexed, indexed: Color.Blue),
      modifiers: {StyleModifier.Bold},
    )

  # Draw mode label with white background (only for active window)
  var currentX = statusLineX
  if isActiveWindow:
    let modeLabelText = fmt" {modeLabel} "
    buffer.setString(currentX, statusLineY, modeLabelText, modeLabelStyle)
    currentX += modeLabelText.len

  # Draw file path
  let
    filePathText =
      if textBuffer.filePath.isSome:
        " " & textBuffer.filePath.get()
      else:
        " [No Name]"
    maxFilePathWidth = statusLineWidth - (currentX - statusLineX) - 1
    truncatedFilePath =
      if filePathText.len > maxFilePathWidth:
        filePathText[0 ..< maxFilePathWidth]
      else:
        filePathText

  buffer.setString(currentX, statusLineY, truncatedFilePath, statusLineStyle)
  currentX += truncatedFilePath.len

  # Prepare line count and percentage display
  let
    lineCountText = block:
      var parts: seq[string] = @[]

      if state.display.showEncoding:
        parts.add(encodingToString(textBuffer.encoding))

      if state.display.showLinePercentage:
        let
          currentLine = state.cursor.line + 1 # Convert to 1-based
          totalLines = textBuffer.len
          percentage =
            if totalLines > 0:
              int((currentLine.float / totalLines.float) * 100.0)
            else:
              0
        parts.add(fmt"{percentage}%")

      if state.display.showLineCount:
        let
          currentLine = state.cursor.line + 1 # Convert to 1-based
          totalLines = textBuffer.len
        parts.add(fmt"{currentLine}/{totalLines}")

      if parts.len > 0:
        " " & parts.join(" ")
      else:
        ""
    lineCountWidth = lineCountText.len

  # Fill the rest of the line with blue background
  let remainingWidth = max(0, (statusLineX + statusLineWidth) - currentX)
  if remainingWidth > 0:
    let blueBackground = " ".repeat(remainingWidth)
    buffer.setString(currentX, statusLineY, blueBackground, statusLineStyle)

  # Draw encoding/line count/percentage with 1 character space from the right end if enabled
  if (
    state.display.showEncoding or state.display.showLineCount or
    state.display.showLinePercentage
  ) and lineCountText.len > 0 and statusLineWidth >= lineCountWidth + 1:
    buffer.setString(
      statusLineX + statusLineWidth - lineCountWidth - 1,
      statusLineY,
      lineCountText,
      statusLineStyle,
    )
