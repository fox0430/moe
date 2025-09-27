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
  state.showStatusLine = not state.showStatusLine

proc setStatusLineVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of the status line
  state.showStatusLine = visible

proc toggleLineCount*(state: var EditorState) =
  ## Toggle the visibility of line count in status line
  state.showLineCount = not state.showLineCount

proc setLineCountVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of line count in status line
  state.showLineCount = visible

proc toggleLinePercentage*(state: var EditorState) =
  ## Toggle the visibility of line percentage in status line
  state.showLinePercentage = not state.showLinePercentage

proc setLinePercentageVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of line percentage in status line
  state.showLinePercentage = visible

proc toggleEncoding*(state: var EditorState) =
  ## Toggle the visibility of encoding in status line
  state.showEncoding = not state.showEncoding

proc setEncodingVisible*(state: var EditorState, visible: bool) =
  ## Set the visibility of encoding in status line
  state.showEncoding = visible

proc renderStatusLine*(
    state: EditorState, textBuffer: TextBuffer, buffer: var Buffer, statusLineY: int
) =
  ## Render the status line at the specified Y position
  if not state.showStatusLine:
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

      if state.showEncoding:
        parts.add(encodingToString(textBuffer.encoding))

      if state.showLinePercentage:
        let
          currentLine = textBuffer.cursor.line + 1 # Convert to 1-based
          totalLines = textBuffer.len
          percentage =
            if totalLines > 0:
              int((currentLine.float / totalLines.float) * 100.0)
            else:
              0
        parts.add(fmt"{percentage}%")

      if state.showLineCount:
        let
          currentLine = textBuffer.cursor.line + 1 # Convert to 1-based
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
  if (state.showEncoding or state.showLineCount or state.showLinePercentage) and
      lineCountText.len > 0 and buffer.area.width >= lineCountWidth + 1:
    buffer.setString(
      buffer.area.x + buffer.area.width - lineCountWidth - 1,
      statusLineY,
      lineCountText,
      statusLineStyle,
    )
