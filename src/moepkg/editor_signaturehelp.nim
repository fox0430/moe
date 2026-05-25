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

## LSP Signature Help request / poll orchestration
##
## The UI side (popup rendering, manager state) lives in signature_help.nim.
## This module owns the editor-side request lifecycle that drives it.

import std/options

import editor_types, lsp_integration, signature_help

proc requestSignatureHelpFromLsp*(e: Editor) =
  ## Request signature help from LSP if in insert mode with paren depth > 0
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled:
    return

  if e.state.mode != EditorMode.Insert:
    return

  let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
  if sigHelpMgr.parenDepth == 0 and not sigHelpMgr.isActive():
    return

  let activeBuffer = e.activeBuffer()

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingSignatureHelpRequestId != 0:
    let (status, resultOpt, _) =
      e.lsp.checkResponse(e.state.lspCache.pendingSignatureHelpRequestId)
    case status
    of lrsPending:
      # Still waiting for response, continue
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingSignatureHelpRequestId = 0
      if resultOpt.isSome:
        let sigHelpOpt = parseSignatureHelpResponse(resultOpt.get)
        if sigHelpOpt.isSome:
          sigHelpMgr.show(
            sigHelpOpt.get, e.activeWindow.cursor.line, e.activeWindow.cursor.column
          )
        else:
          if sigHelpMgr.parenDepth == 0:
            sigHelpMgr.hide()
    of lrsError, lrsTimeout:
      # Request failed or timed out, clear and try again next time
      e.state.lspCache.pendingSignatureHelpRequestId = 0
      return

  # Start a new request
  let reqResult = e.lsp.startSignatureHelpRequest(
    activeBuffer, e.activeWindow.cursor.line, e.activeWindow.cursor.column
  )
  if reqResult.isOk:
    e.state.lspCache.pendingSignatureHelpRequestId = reqResult.get
