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

## LSP Document Link request / poll orchestration (two-stage: links + resolve)

import std/[options, strutils]

import types/editor_types, lsp_service, lsp_integration, buffer, editor_navigation
import lsp/protocol/types as lspTypes

proc findDocumentLinkAtCursor*(
    links: seq[lspTypes.DocumentLink], line, column: int
): Option[lspTypes.DocumentLink] =
  ## Find a document link that contains the cursor position
  ## LSP ranges are half-open intervals [start, end)
  for link in links:
    let startLine = link.range.start.line
    let endLine = link.range.`end`.line
    let startChar = link.range.start.character
    let endChar = link.range.`end`.character

    # Check if cursor is within the link range [start, end)
    if line >= startLine and line <= endLine:
      if line == startLine and line == endLine:
        # Single line link: [startChar, endChar)
        if column >= startChar and column < endChar:
          return some(link)
      elif line == startLine:
        # First line of multi-line link
        if column >= startChar:
          return some(link)
      elif line == endLine:
        # Last line of multi-line link: [0, endChar)
        if column < endChar:
          return some(link)
      else:
        # Cursor is on a middle line of a multi-line link
        return some(link)

  return none(lspTypes.DocumentLink)

proc jumpToDocumentLink(e: Editor, link: lspTypes.DocumentLink): bool =
  ## Jump to a document link target
  ## Returns true if successful
  if link.target.isNone:
    e.state.statusMessage = "Document link has no target"
    return false

  let target = link.target.get

  # Check if the target is a file:// URI
  if target.startsWith("file://"):
    let path = lsp_service.uriToPath(target)
    let activeBuffer = e.activeBuffer()

    # Add current position to jump list before jumping
    e.addToJumpList()

    # Check if it's the same file
    if activeBuffer.filePath.isSome and activeBuffer.filePath.get == path:
      e.state.statusMessage = "Already in this file"
      return true

    let opened = e.openFileInActiveWindow(path)
    if opened.isErr:
      e.state.statusMessage = "Failed to open file: " & opened.error
      return false

    e.state.statusMessage = "Opened: " & path.split('/')[^1]
    return true
  elif target.startsWith("http://") or target.startsWith("https://"):
    # External URL - show message (could open browser in the future)
    e.state.statusMessage = "External link: " & target
    return true
  else:
    # Unknown URI scheme
    e.state.statusMessage = "Unknown link target: " & target
    return false

proc startLspDocumentLinks*(e: Editor): bool =
  ## Start async document links request
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    e.state.statusMessage = "No file path for current buffer"
    return false

  if not e.lsp.hasDocumentLinkSupport(activeBuffer):
    e.state.statusMessage = "Document links not supported"
    return false

  # Cancel any existing requests
  if e.state.lspCache.pendingDocumentLinkRequestId != 0:
    e.lsp.cancelRequest(e.state.lspCache.pendingDocumentLinkRequestId)
    e.state.lspCache.pendingDocumentLinkRequestId = 0
  if e.state.lspCache.pendingDocumentLinkResolveRequestId != 0:
    e.lsp.cancelRequest(e.state.lspCache.pendingDocumentLinkResolveRequestId)
    e.state.lspCache.pendingDocumentLinkResolveRequestId = 0

  # Save cursor position (convert to UTF-16 for LSP comparison)
  let lineText =
    if e.activeWindow.cursor.line >= 0 and e.activeWindow.cursor.line < activeBuffer.len:
      activeBuffer.getLine(e.activeWindow.cursor.line)
    else:
      ""
  e.state.lspCache.pendingDocumentLinkCursorLine = e.activeWindow.cursor.line
  e.state.lspCache.pendingDocumentLinkCursorCol =
    runeIndexToUtf16(lineText, e.activeWindow.cursor.column)

  let reqResult = e.lsp.startDocumentLinkRequest(activeBuffer)
  if reqResult.isErr:
    e.state.statusMessage = "LSP document links failed: " & reqResult.error
    return false

  e.state.lspCache.pendingDocumentLinkRequestId = reqResult.get
  return true

proc pollLspDocumentLinks*(e: Editor) =
  ## Poll for pending document links response (stage 1)
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingDocumentLinkRequestId
  if requestId == 0:
    return

  # Check for response (events were already polled at the top of tick())
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingDocumentLinkRequestId = 0
    # Drop stale response if the user is no longer in Normal/Visual: jumping
    # to a link would swap the buffer under an Insert / overlay session.
    if not e.state.mode.isNormalOrVisualMode or e.state.overlay.isSome:
      return
    if resultOpt.isSome:
      let links = parseDocumentLinksResponse(resultOpt.get)
      if links.len == 0:
        e.state.statusMessage = "No document links found"
        return

      # Find link at saved cursor position
      let cursorLine = e.state.lspCache.pendingDocumentLinkCursorLine
      let cursorCol = e.state.lspCache.pendingDocumentLinkCursorCol
      let linkOpt = findDocumentLinkAtCursor(links, cursorLine, cursorCol)

      if linkOpt.isNone:
        e.state.statusMessage =
          "No link at cursor position (" & $links.len & " links in document)"
        return

      let link = linkOpt.get

      # If link has no target, try to resolve it
      if link.target.isNone:
        let activeBuffer = e.activeBuffer()
        if e.lsp.hasDocumentLinkResolveSupport(activeBuffer):
          # Start resolve request
          let resolveResult = e.lsp.startDocumentLinkResolveRequest(activeBuffer, link)
          if resolveResult.isOk:
            e.state.lspCache.pendingDocumentLinkResolveRequestId = resolveResult.get
            return
          else:
            e.state.statusMessage = "Failed to resolve link: " & resolveResult.error
            return
        else:
          e.state.statusMessage =
            "Document link has no target and resolve not supported"
          return

      discard e.jumpToDocumentLink(link)
    else:
      e.state.statusMessage = "No document links found"
  of lrsError:
    e.state.lspCache.pendingDocumentLinkRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP document links failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingDocumentLinkRequestId = 0
    e.state.statusMessage = "LSP document links timed out"

proc pollLspDocumentLinkResolve*(e: Editor) =
  ## Poll for pending document link resolve response (stage 2)
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingDocumentLinkResolveRequestId
  if requestId == 0:
    return

  # Check for response (events were already polled at the top of tick())
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingDocumentLinkResolveRequestId = 0
    if not e.state.mode.isNormalOrVisualMode or e.state.overlay.isSome:
      return
    if resultOpt.isSome:
      let resolvedLink = parseDocumentLinkResolveResponse(resultOpt.get)
      discard e.jumpToDocumentLink(resolvedLink)
    else:
      e.state.statusMessage = "Document link resolve returned no result"
  of lrsError:
    e.state.lspCache.pendingDocumentLinkResolveRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP document link resolve failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingDocumentLinkResolveRequestId = 0
    e.state.statusMessage = "LSP document link resolve timed out"

proc requestLspDocumentLinks*(e: Editor): bool =
  ## Request document links and jump to link at cursor (async)
  ## Returns true if request was started
  e.startLspDocumentLinks()
