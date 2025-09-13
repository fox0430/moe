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

## Templates for reducing LSP request code duplication in editor modes

import std/[logging, tables]

template checkLspClient*(status, bufStatus): bool =
  ## Check if LSP client is available for the current buffer
  ## Returns true if client exists and is ready, false otherwise
  if not status.lspClients.contains(bufStatus.langId):
    debug "lsp client is not ready"
    false
  else:
    true

template lspRequest*(status, requestProc, errorWriter) =
  ## Generic template for LSP requests with standard error handling
  ##
  ## Usage:
  ##   status.lspRequest(textDocumentDefinition, writeLspDefinitionError)

  if not status.checkLspClient(currentBufStatus):
    return

  let r = waitFor lspClient.requestProc(
    currentBufStatus.id,
    $currentBufStatus.absolutePath,
    currentMainWindowNode.bufferPosition,
  )

  if r.isErr:
    status.commandLine.errorWriter(r.error)
