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

## Tests for signature help functionality

import std/[unittest, options, json]

import pkg/celina

import ../src/moepkg/signature_help {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes
import ../src/moepkg/[color, theme]

proc createSignatureHelp(
    label: string,
    params: seq[string] = @[],
    activeParam: int = 0,
    documentation: string = "",
): SignatureHelp =
  ## Helper to create a SignatureHelp object for testing
  var paramInfos: seq[ParameterInformation] = @[]
  for p in params:
    paramInfos.add(ParameterInformation(label: p, documentation: none(JsonNode)))

  var sigInfo = SignatureInformation(
    label: label,
    documentation:
      if documentation.len > 0:
        some(%documentation)
      else:
        none(JsonNode),
    parameters:
      if paramInfos.len > 0:
        some(paramInfos)
      else:
        none(seq[ParameterInformation]),
    activeParameter: some(activeParam),
  )

  SignatureHelp(
    signatures: @[sigInfo], activeSignature: some(0), activeParameter: some(activeParam)
  )

suite "SignatureHelp - newSignatureHelpManager":
  test "Creates manager with idle state":
    let mgr = newSignatureHelpManager()

    check mgr.state == shsIdle
    check mgr.display.signature == ""
    check mgr.display.activeParamStart == -1
    check mgr.display.activeParamEnd == -1
    check mgr.display.documentation == ""
    check mgr.triggerLine == 0
    check mgr.triggerCol == 0
    check mgr.parenDepth == 0

suite "SignatureHelp - isActive":
  test "Returns false when idle":
    let mgr = newSignatureHelpManager()

    check mgr.isActive == false

  test "Returns true when active":
    let mgr = newSignatureHelpManager()
    let sigHelp =
      createSignatureHelp("func(a: int, b: string)", @["a: int", "b: string"])
    mgr.show(sigHelp, 5, 10)

    check mgr.isActive == true

suite "SignatureHelp - isTriggerChar":
  test "Opening paren is trigger char":
    check isTriggerChar('(') == true

  test "Comma is trigger char":
    check isTriggerChar(',') == true

  test "Closing paren is not trigger char":
    check isTriggerChar(')') == false

  test "Regular characters are not trigger chars":
    check isTriggerChar('a') == false
    check isTriggerChar(' ') == false
    check isTriggerChar(':') == false

suite "SignatureHelp - isRetriggerChar":
  test "Comma is retrigger char":
    check isRetriggerChar(',') == true

  test "Opening paren is not retrigger char":
    check isRetriggerChar('(') == false

  test "Regular characters are not retrigger chars":
    check isRetriggerChar('a') == false
    check isRetriggerChar(' ') == false

suite "SignatureHelp - isCloseChar":
  test "Closing paren is close char":
    check isCloseChar(')') == true

  test "Opening paren is not close char":
    check isCloseChar('(') == false

  test "Regular characters are not close chars":
    check isCloseChar('a') == false
    check isCloseChar(',') == false

suite "SignatureHelp - show":
  test "Shows signature help with valid signature":
    let mgr = newSignatureHelpManager()
    let sigHelp =
      createSignatureHelp("func(a: int, b: string)", @["a: int", "b: string"])

    mgr.show(sigHelp, 5, 10)

    check mgr.state == shsActive
    check mgr.display.signature == "func(a: int, b: string)"
    check mgr.triggerLine == 5
    check mgr.triggerCol == 10

  test "Does not show with empty signatures":
    let mgr = newSignatureHelpManager()
    let sigHelp = SignatureHelp(
      signatures: @[], activeSignature: none(int), activeParameter: none(int)
    )

    mgr.show(sigHelp, 5, 10)

    check mgr.state == shsIdle
    check mgr.display.signature == ""

  test "Shows with documentation":
    let mgr = newSignatureHelpManager()
    let sigHelp = createSignatureHelp(
      "func(a: int)", @["a: int"], activeParam = 0, documentation = "This is a function"
    )

    mgr.show(sigHelp, 0, 0)

    check mgr.state == shsActive
    check mgr.display.documentation == "This is a function"

  test "Highlights active parameter":
    let mgr = newSignatureHelpManager()
    let sigHelp = createSignatureHelp(
      "func(a: int, b: string)", @["a: int", "b: string"], activeParam = 0
    )

    mgr.show(sigHelp, 0, 0)

    check mgr.display.activeParamStart >= 0
    check mgr.display.activeParamEnd > mgr.display.activeParamStart

suite "SignatureHelp - hide":
  test "Hides active signature help":
    let mgr = newSignatureHelpManager()
    let sigHelp = createSignatureHelp("func(a: int)", @["a: int"])
    mgr.show(sigHelp, 0, 0)

    check mgr.state == shsActive

    mgr.hide()

    check mgr.state == shsIdle
    check mgr.display.signature == ""
    check mgr.display.activeParamStart == -1
    check mgr.display.activeParamEnd == -1
    check mgr.display.documentation == ""
    check mgr.parenDepth == 0

  test "Hides idle signature help (no-op)":
    let mgr = newSignatureHelpManager()

    mgr.hide()

    check mgr.state == shsIdle

suite "SignatureHelp - incrementParenDepth":
  test "Increments paren depth":
    let mgr = newSignatureHelpManager()

    check mgr.parenDepth == 0

    mgr.incrementParenDepth()
    check mgr.parenDepth == 1

    mgr.incrementParenDepth()
    check mgr.parenDepth == 2

suite "SignatureHelp - decrementParenDepth":
  test "Decrements paren depth":
    let mgr = newSignatureHelpManager()
    mgr.parenDepth = 3

    mgr.decrementParenDepth()
    check mgr.parenDepth == 2

    mgr.decrementParenDepth()
    check mgr.parenDepth == 1

  test "Does not go below zero":
    let mgr = newSignatureHelpManager()
    mgr.parenDepth = 0

    mgr.decrementParenDepth()

    check mgr.parenDepth == 0

  test "Hides when paren depth reaches zero":
    let mgr = newSignatureHelpManager()
    let sigHelp = createSignatureHelp("func(a: int)", @["a: int"])
    mgr.show(sigHelp, 0, 0)
    mgr.parenDepth = 1

    check mgr.state == shsActive

    mgr.decrementParenDepth()

    check mgr.parenDepth == 0
    check mgr.state == shsIdle

suite "SignatureHelp - calculateSignatureHelpPosition":
  test "Positions popup above cursor":
    let pos = calculateSignatureHelpPosition(
      cursorX = 10, cursorY = 20, termWidth = 80, termHeight = 24, signatureLen = 30
    )

    # Popup should be above cursor (y < cursorY)
    check pos.y < 20
    check pos.x == 10
    check pos.height == 3 # 1 line for content + 2 for border

  test "Positions popup below cursor when no space above":
    let pos = calculateSignatureHelpPosition(
      cursorX = 10,
      cursorY = 1, # Not enough space above
      termWidth = 80,
      termHeight = 24,
      signatureLen = 30,
    )

    # Popup should be below cursor
    check pos.y == 2 # cursorY + 1

  test "Adjusts X when popup would extend past right edge":
    let pos = calculateSignatureHelpPosition(
      cursorX = 70, cursorY = 12, termWidth = 80, termHeight = 24, signatureLen = 30
    )

    # Popup should be shifted left to fit
    check pos.x + pos.width <= 80

  test "Uses minimum width when content is short":
    let pos = calculateSignatureHelpPosition(
      cursorX = 10, cursorY = 12, termWidth = 80, termHeight = 24, signatureLen = 5
    )

    # Width should be at least MinPopupWidth + 2 (for border)
    check pos.width >= MinPopupWidth + 2

  test "Limits width to maximum":
    let pos = calculateSignatureHelpPosition(
      cursorX = 0,
      cursorY = 12,
      termWidth = 200,
      termHeight = 24,
      signatureLen = 200, # Very long signature
    )

    # Width should not exceed MaxPopupWidth + 2 (for border)
    check pos.width <= MaxPopupWidth + 2

suite "SignatureHelp - renderSignatureHelpPopup":
  test "Renders popup content to buffer":
    let display = SignatureHelpDisplay(
      signature: "Hello", activeParamStart: -1, activeParamEnd: -1, documentation: ""
    )
    let pos = SignatureHelpPopupPosition(x: 5, y: 5, width: 10, height: 3)

    var termBuffer = newBuffer(80, 24)

    renderSignatureHelpPopup(termBuffer, display, pos, showBorder = true)

    # Check top border
    check termBuffer[5, 5].symbol == "┌"
    check termBuffer[14, 5].symbol == "┐"
    # Check content area exists
    check termBuffer[5, 6].symbol == "│"
    check termBuffer[14, 6].symbol == "│"
    # Check bottom border
    check termBuffer[5, 7].symbol == "└"
    check termBuffer[14, 7].symbol == "┘"

  test "Does nothing with empty signature":
    let display = SignatureHelpDisplay(
      signature: "", activeParamStart: -1, activeParamEnd: -1, documentation: ""
    )
    let pos = SignatureHelpPopupPosition(x: 0, y: 0, width: 10, height: 3)

    var termBuffer = newBuffer(80, 24)

    # Should not crash
    renderSignatureHelpPopup(termBuffer, display, pos, showBorder = true)

    # Buffer should remain unchanged (except for any default initialization)
    check termBuffer[0, 0].symbol != "┌"

  test "Renders without border when showBorder is false":
    let display = SignatureHelpDisplay(
      signature: "test", activeParamStart: -1, activeParamEnd: -1, documentation: ""
    )
    let pos = SignatureHelpPopupPosition(x: 0, y: 0, width: 10, height: 3)

    var termBuffer = newBuffer(80, 24)

    renderSignatureHelpPopup(termBuffer, display, pos, showBorder = false)

    # No border characters
    check termBuffer[0, 0].symbol != "┌"
    check termBuffer[9, 0].symbol != "┐"

  test "Wide char signature writes continuation cell to prevent ghost":
    # Wide (2-col) characters must set an empty continuation cell at x+1 so
    # celina's diff can repaint the second column on popup close.
    let display = SignatureHelpDisplay(
      signature: "日本語",
      activeParamStart: -1,
      activeParamEnd: -1,
      documentation: "",
    )
    let pos = SignatureHelpPopupPosition(x: 0, y: 0, width: 10, height: 3)

    var termBuffer = newBuffer(80, 24)
    renderSignatureHelpPopup(termBuffer, display, pos, showBorder = true)

    # Content starts at (1, 1) due to border
    check termBuffer[1, 1].symbol == "日"
    check termBuffer[2, 1].symbol == ""
    check termBuffer[2, 1].style == termBuffer[1, 1].style
    check termBuffer[3, 1].symbol == "本"
    check termBuffer[4, 1].symbol == ""
    check termBuffer[4, 1].style == termBuffer[3, 1].style

suite "SignatureHelp - styles":
  test "signatureHelpNormalStyle uses the popupWindow theme color":
    initDefaultTheme()
    check signatureHelpNormalStyle() == getThemeStyle(EditorColorPairIndex.popupWindow)

  test "signatureHelpHighlightStyle uses the active parameter theme color with bold":
    initDefaultTheme()
    check signatureHelpHighlightStyle() ==
      getThemeStyle(
        EditorColorPairIndex.popupWindowActiveParameter, {StyleModifier.Bold}
      )

  test "signatureHelpBorderStyle uses the popupWindowBorder theme color":
    initDefaultTheme()
    check signatureHelpBorderStyle() ==
      getThemeStyle(EditorColorPairIndex.popupWindowBorder)

suite "SignatureHelp - constants":
  test "SignatureHelpTriggerChars contains '(' and ','":
    check '(' in SignatureHelpTriggerChars
    check ',' in SignatureHelpTriggerChars

  test "SignatureHelpRetriggerChars contains ','":
    check ',' in SignatureHelpRetriggerChars

  test "SignatureHelpCloseChars contains ')'":
    check ')' in SignatureHelpCloseChars

  test "MinPopupWidth is 20":
    check MinPopupWidth == 20

  test "MaxPopupWidth is 80":
    check MaxPopupWidth == 80

  test "PopupPadding is 2":
    check PopupPadding == 2

suite "SignatureHelp - updateFromSignatureHelp":
  test "Updates display from SignatureHelp":
    let mgr = newSignatureHelpManager()
    let sigHelp =
      createSignatureHelp("func(a: int, b: string)", @["a: int", "b: string"])

    mgr.updateFromSignatureHelp(sigHelp)

    check mgr.display.signature == "func(a: int, b: string)"

  test "Updates active parameter highlighting":
    let mgr = newSignatureHelpManager()
    let sigHelp = createSignatureHelp(
      "func(a: int, b: string)", @["a: int", "b: string"], activeParam = 1
    )

    mgr.updateFromSignatureHelp(sigHelp)

    # Should highlight "b: string"
    check mgr.display.activeParamStart >= 0
    check mgr.display.activeParamEnd > mgr.display.activeParamStart

  test "Extracts documentation from string":
    let mgr = newSignatureHelpManager()
    let sigHelp = createSignatureHelp(
      "func(a: int)", @["a: int"], activeParam = 0, documentation = "A helpful function"
    )

    mgr.updateFromSignatureHelp(sigHelp)

    check mgr.display.documentation == "A helpful function"

  test "Extracts documentation from MarkupContent":
    let mgr = newSignatureHelpManager()

    var sigInfo = SignatureInformation(
      label: "func(a: int)",
      documentation: some(%*{"kind": "markdown", "value": "**Bold** documentation"}),
      parameters:
        some(@[ParameterInformation(label: "a: int", documentation: none(JsonNode))]),
      activeParameter: some(0),
    )

    let sigHelp = SignatureHelp(
      signatures: @[sigInfo], activeSignature: some(0), activeParameter: some(0)
    )

    mgr.updateFromSignatureHelp(sigHelp)

    check mgr.display.documentation == "**Bold** documentation"

suite "SignatureHelp - multiple signatures":
  test "Uses active signature index":
    let mgr = newSignatureHelpManager()

    let sig1 = SignatureInformation(
      label: "func()",
      documentation: some(%"First overload"),
      parameters: none(seq[ParameterInformation]),
      activeParameter: none(int),
    )
    let sig2 = SignatureInformation(
      label: "func(a: int)",
      documentation: some(%"Second overload"),
      parameters:
        some(@[ParameterInformation(label: "a: int", documentation: none(JsonNode))]),
      activeParameter: some(0),
    )

    let sigHelp = SignatureHelp(
      signatures: @[sig1, sig2],
      activeSignature: some(1), # Second signature
      activeParameter: some(0),
    )

    mgr.show(sigHelp, 0, 0)

    check mgr.display.signature == "func(a: int)"
    check mgr.display.documentation == "Second overload"

  test "Defaults to first signature when activeSignature is none":
    let mgr = newSignatureHelpManager()

    let sig1 = SignatureInformation(
      label: "func()",
      documentation: some(%"First overload"),
      parameters: none(seq[ParameterInformation]),
      activeParameter: none(int),
    )
    let sig2 = SignatureInformation(
      label: "func(a: int)",
      documentation: some(%"Second overload"),
      parameters:
        some(@[ParameterInformation(label: "a: int", documentation: none(JsonNode))]),
      activeParameter: some(0),
    )

    let sigHelp = SignatureHelp(
      signatures: @[sig1, sig2],
      activeSignature: none(int), # No active signature specified
      activeParameter: none(int),
    )

    mgr.show(sigHelp, 0, 0)

    check mgr.display.signature == "func()"
    check mgr.display.documentation == "First overload"

suite "SignatureHelp - edge cases":
  test "updateFromSignatureHelp with empty signatures":
    let mgr = newSignatureHelpManager()
    let sigHelp = SignatureHelp(
      signatures: @[], activeSignature: none(int), activeParameter: none(int)
    )

    mgr.updateFromSignatureHelp(sigHelp)

    check mgr.display.signature == ""
    check mgr.display.activeParamStart == -1
    check mgr.display.activeParamEnd == -1

  test "updateFromSignatureHelp with invalid activeSignature index":
    let mgr = newSignatureHelpManager()
    let sigInfo = SignatureInformation(
      label: "func()",
      documentation: some(%"Doc"),
      parameters: none(seq[ParameterInformation]),
      activeParameter: none(int),
    )
    let sigHelp = SignatureHelp(
      signatures: @[sigInfo],
      activeSignature: some(99), # Invalid index
      activeParameter: none(int),
    )

    mgr.updateFromSignatureHelp(sigHelp)

    # Should not crash, documentation should be empty due to invalid index
    check mgr.display.documentation == ""

  test "updateFromSignatureHelp with negative activeSignature":
    let mgr = newSignatureHelpManager()
    let sigInfo = SignatureInformation(
      label: "func()",
      documentation: some(%"Doc"),
      parameters: none(seq[ParameterInformation]),
      activeParameter: none(int),
    )
    let sigHelp = SignatureHelp(
      signatures: @[sigInfo],
      activeSignature: some(-1), # Negative index
      activeParameter: none(int),
    )

    mgr.updateFromSignatureHelp(sigHelp)

    check mgr.display.documentation == ""

  test "updateFromSignatureHelp with JObject without value key":
    let mgr = newSignatureHelpManager()
    let sigInfo = SignatureInformation(
      label: "func()",
      documentation: some(%*{"kind": "markdown", "other": "data"}), # No "value" key
      parameters: none(seq[ParameterInformation]),
      activeParameter: none(int),
    )
    let sigHelp = SignatureHelp(
      signatures: @[sigInfo], activeSignature: some(0), activeParameter: none(int)
    )

    mgr.updateFromSignatureHelp(sigHelp)

    # Should not crash, should have empty documentation
    check mgr.display.documentation == ""

  test "updateFromSignatureHelp with JArray documentation":
    let mgr = newSignatureHelpManager()
    let sigInfo = SignatureInformation(
      label: "func()",
      documentation: some(%*["item1", "item2"]), # JArray type
      parameters: none(seq[ParameterInformation]),
      activeParameter: none(int),
    )
    let sigHelp = SignatureHelp(
      signatures: @[sigInfo], activeSignature: some(0), activeParameter: none(int)
    )

    mgr.updateFromSignatureHelp(sigHelp)

    # Should handle JArray gracefully (falls into else branch)
    check mgr.display.documentation == ""

  test "updateFromSignatureHelp with no documentation":
    let mgr = newSignatureHelpManager()
    let sigInfo = SignatureInformation(
      label: "func(a: int)",
      documentation: none(JsonNode),
      parameters:
        some(@[ParameterInformation(label: "a: int", documentation: none(JsonNode))]),
      activeParameter: some(0),
    )
    let sigHelp = SignatureHelp(
      signatures: @[sigInfo], activeSignature: some(0), activeParameter: some(0)
    )

    mgr.updateFromSignatureHelp(sigHelp)

    check mgr.display.signature == "func(a: int)"
    check mgr.display.documentation == ""

  test "Signature without parameters":
    let mgr = newSignatureHelpManager()
    let sigHelp = createSignatureHelp("func()", @[])

    mgr.show(sigHelp, 0, 0)

    check mgr.state == shsActive
    check mgr.display.signature == "func()"
    check mgr.display.activeParamStart == -1
    check mgr.display.activeParamEnd == -1

suite "SignatureHelp - renderSignatureHelpPopup advanced":
  test "Renders with highlighted active parameter":
    let display = SignatureHelpDisplay(
      signature: "func(a: int, b: string)",
      activeParamStart: 5, # Start of "a: int"
      activeParamEnd: 11, # End of "a: int"
      documentation: "",
    )
    let pos = SignatureHelpPopupPosition(x: 0, y: 0, width: 30, height: 3)

    var termBuffer = newBuffer(80, 24)

    renderSignatureHelpPopup(termBuffer, display, pos, showBorder = true)

    # Check that content is rendered (left border + content)
    check termBuffer[0, 1].symbol == "│"

    # Verify highlighted portion uses the active-parameter highlight style
    # Characters at index 5-10 should have highlight style
    check termBuffer[6, 1].style == signatureHelpHighlightStyle()

    # Characters before highlight should have the normal style
    check termBuffer[1, 1].style == signatureHelpNormalStyle()

  test "Renders Unicode signature correctly":
    let display = SignatureHelpDisplay(
      signature: "関数(引数: 整数)",
      activeParamStart: -1,
      activeParamEnd: -1,
      documentation: "",
    )
    let pos = SignatureHelpPopupPosition(x: 0, y: 0, width: 25, height: 3)

    var termBuffer = newBuffer(80, 24)

    renderSignatureHelpPopup(termBuffer, display, pos, showBorder = true)

    # Should not crash and render border
    check termBuffer[0, 0].symbol == "┌"
    check termBuffer[0, 2].symbol == "└"

  test "Handles popup at buffer boundary":
    let display = SignatureHelpDisplay(
      signature: "test", activeParamStart: -1, activeParamEnd: -1, documentation: ""
    )
    # Position popup near edge
    let pos = SignatureHelpPopupPosition(x: 75, y: 0, width: 10, height: 3)

    var termBuffer = newBuffer(80, 24)

    # Should not crash even if parts are outside buffer
    renderSignatureHelpPopup(termBuffer, display, pos, showBorder = true)

    check termBuffer[75, 0].symbol == "┌"

  test "Fills remaining space with background":
    let display = SignatureHelpDisplay(
      signature: "Hi", # Short signature
      activeParamStart: -1,
      activeParamEnd: -1,
      documentation: "",
    )
    let pos = SignatureHelpPopupPosition(x: 0, y: 0, width: 15, height: 3)

    var termBuffer = newBuffer(80, 24)

    renderSignatureHelpPopup(termBuffer, display, pos, showBorder = true)

    # Content area should be filled after "Hi"
    # Position 1 = 'H', 2 = 'i', 3+ should be spaces with normal style
    check termBuffer[3, 1].symbol == " "
    check termBuffer[3, 1].style == signatureHelpNormalStyle()

  test "Truncates long signature that exceeds content width":
    let display = SignatureHelpDisplay(
      signature: "veryLongFunctionNameWithManyParameters(a: int, b: string, c: float)",
      activeParamStart: -1,
      activeParamEnd: -1,
      documentation: "",
    )
    # Small width
    let pos = SignatureHelpPopupPosition(x: 0, y: 0, width: 20, height: 3)

    var termBuffer = newBuffer(80, 24)

    renderSignatureHelpPopup(termBuffer, display, pos, showBorder = true)

    # Should render without crash, border intact
    check termBuffer[0, 0].symbol == "┌"
    check termBuffer[19, 0].symbol == "┐"
    check termBuffer[0, 1].symbol == "│"
    check termBuffer[19, 1].symbol == "│"

suite "SignatureHelp - calculateSignatureHelpPosition edge cases":
  test "Handles zero terminal dimensions":
    let pos = calculateSignatureHelpPosition(
      cursorX = 0, cursorY = 0, termWidth = 0, termHeight = 0, signatureLen = 10
    )

    # Should not crash
    check pos.height == 3

  test "Handles cursor at origin with no space above":
    let pos = calculateSignatureHelpPosition(
      cursorX = 0, cursorY = 0, termWidth = 80, termHeight = 24, signatureLen = 10
    )

    # Should position below cursor
    check pos.y == 1

  test "X adjustment when cursor near right edge":
    let pos = calculateSignatureHelpPosition(
      cursorX = 79, cursorY = 10, termWidth = 80, termHeight = 24, signatureLen = 30
    )

    # X should be adjusted so popup fits
    check pos.x >= 0
    check pos.x + pos.width <= 80

  test "Grown bottom reserve keeps below-cursor popup clear of command line":
    # Cursor at y=1 so above-cursor placement fails and popup goes below.
    let steady = calculateSignatureHelpPosition(
      cursorX = 10, cursorY = 1, termWidth = 80, termHeight = 24, signatureLen = 30
    )
    check steady.y == 2 # cursorY + 1

    # A grown bottom area (e.g. 5-line message + status + padding) must
    # push the popup back up so it does not overlap the command line.
    let grown = calculateSignatureHelpPosition(
      cursorX = 10,
      cursorY = 1,
      termWidth = 80,
      termHeight = 24,
      signatureLen = 30,
      bottomReserve = 20,
    )
    check grown.y + grown.height <= 24 - 20

suite "SignatureHelp - calculateSignatureHelpAnchorX":
  test "Pins anchor when caret sits at the trigger":
    let anchor = calculateSignatureHelpAnchorX(
      screenCursorX = 12,
      triggerLine = 3,
      triggerCol = 8,
      cursorLine = 3,
      cursorCol = 8,
      triggerCellX = 8,
      cursorCellX = 8,
    )
    check anchor == 12

  test "Shifts anchor left by the display width of typed arguments":
    let anchor = calculateSignatureHelpAnchorX(
      screenCursorX = 16,
      triggerLine = 3,
      triggerCol = 8,
      cursorLine = 3,
      cursorCol = 12,
      triggerCellX = 8,
      cursorCellX = 12,
    )
    # Caret advanced 4 cells past the trigger; anchor rewinds by the same.
    check anchor == 12

  test "Honors wide-cell characters via the caller-supplied cell offsets":
    let anchor = calculateSignatureHelpAnchorX(
      screenCursorX = 20,
      triggerLine = 3,
      triggerCol = 8,
      cursorLine = 3,
      cursorCol = 10,
      triggerCellX = 8,
      cursorCellX = 14, # 2 chars but 6 cells (e.g. two double-width runes)
    )
    check anchor == 14

  test "Clamps anchor to zero rather than going negative":
    let anchor = calculateSignatureHelpAnchorX(
      screenCursorX = 2,
      triggerLine = 3,
      triggerCol = 0,
      cursorLine = 3,
      cursorCol = 10,
      triggerCellX = 0,
      cursorCellX = 10,
    )
    check anchor == 0

  test "Falls back to screenCursorX when caret is on a different line":
    let anchor = calculateSignatureHelpAnchorX(
      screenCursorX = 5,
      triggerLine = 3,
      triggerCol = 8,
      cursorLine = 4,
      cursorCol = 2,
      triggerCellX = 8,
      cursorCellX = 2,
    )
    check anchor == 5

  test "Falls back to screenCursorX when caret is before the trigger":
    let anchor = calculateSignatureHelpAnchorX(
      screenCursorX = 6,
      triggerLine = 3,
      triggerCol = 10,
      cursorLine = 3,
      cursorCol = 6,
      triggerCellX = 10,
      cursorCellX = 6,
    )
    check anchor == 6

  test "Falls back to screenCursorX when the trigger column is uninitialised":
    let anchor = calculateSignatureHelpAnchorX(
      screenCursorX = 9,
      triggerLine = 3,
      triggerCol = -1,
      cursorLine = 3,
      cursorCol = 4,
      triggerCellX = 0,
      cursorCellX = 4,
    )
    check anchor == 9
