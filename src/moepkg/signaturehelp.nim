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

## LSP Signature Help display
##
## This module provides signature help functionality for Insert mode.
## It displays function signatures and parameter information
## when typing function calls.

import std/[options, unicode, json]

import pkg/celina

import lspintegration
import lsp/protocol/types as lspTypes

type
  SignatureHelpState* = enum
    shsIdle ## No signature help active
    shsActive ## Signature help is being displayed

  SignatureHelpDisplay* = object ## Signature help popup state
    signature*: string ## The function signature to display
    activeParamStart*: int ## Start position of active parameter (-1 if none)
    activeParamEnd*: int ## End position of active parameter (-1 if none)
    documentation*: string ## Optional documentation

  SignatureHelpManager* = ref object ## Manages signature help state
    state*: SignatureHelpState
    display*: SignatureHelpDisplay
    triggerLine*: int ## Line where signature help was triggered
    triggerCol*: int ## Column where signature help was triggered
    parenDepth*: int ## Current parenthesis depth

# Trigger characters for signature help
const
  SignatureHelpTriggerChars* = ['(', ',']
  SignatureHelpRetriggerChars* = [',']
  SignatureHelpCloseChars* = [')']
  MinPopupWidth* = 20
  MaxPopupWidth* = 80
  PopupPadding* = 2

proc newSignatureHelpManager*(): SignatureHelpManager =
  ## Create a new signature help manager
  SignatureHelpManager(
    state: shsIdle,
    display: SignatureHelpDisplay(
      signature: "", activeParamStart: -1, activeParamEnd: -1, documentation: ""
    ),
    triggerLine: 0,
    triggerCol: 0,
    parenDepth: 0,
  )

proc isActive*(mgr: SignatureHelpManager): bool =
  ## Check if signature help is active
  mgr.state == shsActive

proc isTriggerChar*(c: char): bool =
  ## Check if character triggers signature help
  c in SignatureHelpTriggerChars

proc isRetriggerChar*(c: char): bool =
  ## Check if character retriggers signature help
  c in SignatureHelpRetriggerChars

proc isCloseChar*(c: char): bool =
  ## Check if character closes signature help
  c in SignatureHelpCloseChars

proc updateFromSignatureHelp*(mgr: SignatureHelpManager, sigHelp: SignatureHelp) =
  ## Update display from LSP SignatureHelp response
  let paramInfo = getParameterInfo(sigHelp)
  mgr.display.signature = paramInfo.label
  mgr.display.activeParamStart = paramInfo.start
  mgr.display.activeParamEnd = paramInfo.stop

  # Extract documentation if available
  if sigHelp.signatures.len > 0:
    let activeIdx = sigHelp.activeSignature.get(0)
    if activeIdx >= 0 and activeIdx < sigHelp.signatures.len:
      let sig = sigHelp.signatures[activeIdx]
      if sig.documentation.isSome:
        let doc = sig.documentation.get
        case doc.kind
        of JString:
          mgr.display.documentation = doc.getStr
        of JObject:
          if doc.hasKey("value"):
            mgr.display.documentation = doc["value"].getStr
        else:
          mgr.display.documentation = ""
      else:
        mgr.display.documentation = ""

proc show*(mgr: SignatureHelpManager, sigHelp: SignatureHelp, line, col: int) =
  ## Show signature help
  if sigHelp.signatures.len == 0:
    mgr.state = shsIdle
    return

  mgr.updateFromSignatureHelp(sigHelp)
  mgr.triggerLine = line
  mgr.triggerCol = col
  mgr.state = shsActive

proc hide*(mgr: SignatureHelpManager) =
  ## Hide signature help
  mgr.state = shsIdle
  mgr.display.signature = ""
  mgr.display.activeParamStart = -1
  mgr.display.activeParamEnd = -1
  mgr.display.documentation = ""
  mgr.parenDepth = 0

proc incrementParenDepth*(mgr: SignatureHelpManager) =
  ## Increment paren depth (called when '(' is typed)
  inc mgr.parenDepth

proc decrementParenDepth*(mgr: SignatureHelpManager) =
  ## Decrement paren depth (called when ')' is typed)
  if mgr.parenDepth > 0:
    dec mgr.parenDepth
  if mgr.parenDepth == 0:
    mgr.hide()

# Popup rendering

type SignatureHelpPopupPosition* = object
  x*, y*: int
  width*, height*: int

let
  signatureHelpNormalStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.White),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    modifiers: {},
  )
  signatureHelpHighlightStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    modifiers: {StyleModifier.Bold},
  )
  signatureHelpBorderStyle* = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    modifiers: {},
  )

proc calculateSignatureHelpPosition*(
    cursorX, cursorY: int, termWidth, termHeight: int, signatureLen: int
): SignatureHelpPopupPosition =
  ## Calculate popup position and size
  ## Signature help appears above the cursor line
  let contentWidth = min(max(signatureLen + PopupPadding, MinPopupWidth), MaxPopupWidth)
  let popupWidth = contentWidth + 2 # +2 for border
  let popupHeight = 3 # 1 line for content + 2 for border

  var x = cursorX
  var y = cursorY - popupHeight # Above cursor

  # Adjust X if popup would extend past right edge
  if x + popupWidth > termWidth:
    x = max(0, termWidth - popupWidth)

  # If not enough space above, try below
  if y < 0:
    y = cursorY + 1

  SignatureHelpPopupPosition(x: x, y: y, width: popupWidth, height: popupHeight)

proc renderSignatureHelpPopup*(
    termBuffer: var Buffer,
    display: SignatureHelpDisplay,
    pos: SignatureHelpPopupPosition,
    showBorder: bool = true,
) =
  ## Render signature help popup to terminal buffer
  if display.signature.len == 0:
    return

  # Calculate content area (inside border)
  let contentX =
    if showBorder:
      pos.x + 1
    else:
      pos.x
  let contentY =
    if showBorder:
      pos.y + 1
    else:
      pos.y
  let contentWidth =
    if showBorder:
      pos.width - 2
    else:
      pos.width

  # Draw border if enabled
  if showBorder:
    # Top border
    if pos.y >= 0 and pos.y < termBuffer.area.height:
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        termBuffer[pos.x, pos.y] = cell("┌", signatureHelpBorderStyle)
      for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
        if x >= 0:
          termBuffer[x, pos.y] = cell("─", signatureHelpBorderStyle)
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        termBuffer[pos.x + pos.width - 1, pos.y] = cell("┐", signatureHelpBorderStyle)

    # Side borders and content
    if contentY >= 0 and contentY < termBuffer.area.height:
      # Left border
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        termBuffer[pos.x, contentY] = cell("│", signatureHelpBorderStyle)

      # Content - signature with highlighted active parameter
      var x = contentX
      var charIdx = 0
      for r in display.signature.runes:
        if x >= contentX + contentWidth or x >= termBuffer.area.width:
          break

        # Determine style based on whether this character is in the active parameter
        let style =
          if display.activeParamStart >= 0 and charIdx >= display.activeParamStart and
              charIdx < display.activeParamEnd:
            signatureHelpHighlightStyle
          else:
            signatureHelpNormalStyle

        termBuffer[x, contentY] = cell($r, style)
        x += runeWidth(r)
        inc charIdx

      # Fill remaining space with background
      while x < contentX + contentWidth and x < termBuffer.area.width:
        termBuffer[x, contentY] = cell(" ", signatureHelpNormalStyle)
        inc x

      # Right border
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        termBuffer[pos.x + pos.width - 1, contentY] =
          cell("│", signatureHelpBorderStyle)

    # Bottom border
    let bottomY = contentY + 1
    if bottomY >= 0 and bottomY < termBuffer.area.height:
      if pos.x >= 0 and pos.x < termBuffer.area.width:
        termBuffer[pos.x, bottomY] = cell("└", signatureHelpBorderStyle)
      for x in pos.x + 1 ..< min(pos.x + pos.width - 1, termBuffer.area.width):
        if x >= 0:
          termBuffer[x, bottomY] = cell("─", signatureHelpBorderStyle)
      if pos.x + pos.width - 1 >= 0 and pos.x + pos.width - 1 < termBuffer.area.width:
        termBuffer[pos.x + pos.width - 1, bottomY] =
          cell("┘", signatureHelpBorderStyle)
