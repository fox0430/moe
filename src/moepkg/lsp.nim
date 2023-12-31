#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[options, tables, json, logging, strformat]

import pkg/results

import lsp/[client, utils]
import editorstatus, windownode, popupwindow, unicodeext, independentutils,
       gapbuffer, messages, ui, commandline, bufferstatus, syntaxcheck

template isLspResponse*(status: EditorStatus): bool =
  status.lspClients.contains(currentBufStatus.langId) and
  (let r = lspClient.readable; r.isOk and r.get)

template isWaitingLspResponse(status: var EditorStatus): bool =
  status.lspClients[currentBufStatus.langId].waitingResponse.isSome

proc lspInitialized(
  status: var EditorStatus,
  initializeRes: JsonNode): Result[(), string] =
    ## Send notifications for initialize LSP.

    block:
      let r = lspClient.initCapacities(initializeRes)
      if r.isErr:
        return Result[(), string].err r.error

    block:
      # Initialized notification
      let err = lspClient.initialized
      if err.isErr:
        return Result[(), string].err err.error

    block:
      # workspace/didChangeConfiguration notification
      let err = lspClient.workspaceDidChangeConfiguration
      if err.isErr:
        return Result[(), string].err err.error

    let langId = $status.bufStatus[^1].extension

    block:
      # textDocument/diOpen notification
      let err = lspClient.textDocumentDidOpen(
        $status.bufStatus[^1].path.absolutePath,
        langId,
        status.bufStatus[^1].buffer.toString)
      if err.isErr:
        return Result[(), string].err err.error

    status.commandLine.writeLspInitialized(
      status.settings.lsp.languages[langId].command)

    return Result[(), string].ok ()

proc initHoverWindow(
  windowNode: WindowNode,
  hoverContent: HoverContent): PopupWindow =
    ## Return a popup window for textDocument/hover.

    const Margin = ru" "
    var buffer: seq[Runes]
    if hoverContent.title.len > 0:
      buffer = @[Margin & hoverContent.title & Margin, ru""]
    for line in hoverContent.description:
      buffer.add Margin & line & Margin

    let
      absPositon = windowNode.absolutePosition
      expectPosition = Position(y: absPositon.y + 1, x: absPositon.x + 1)
    result = initPopupWindow(
      expectPosition,
      Size(h: buffer.len, w: buffer.maxLen),
      buffer)

    let
      minPosition = Position(y: windowNode.y, x: windowNode.x)
      maxPostion = Position(
        y: windowNode.y + windowNode.h,
        x: windowNode.x + windowNode.w)
    result.autoMoveAndResize(minPosition, maxPostion)
    result.update

proc lspHover*(status: var EditorStatus, res: JsonNode): Result[(), string] =
  ## Display the hover on a popup window until any key is pressed.
  ## textDocument/hover.
  ## TODO: Add tests after resolving the forever key waiting problem.

  lspClient.clearWaitingResponse

  let hover = parseTextDocumentHoverResponse(res)
  if hover.isErr:
    return Result[(), string].err hover.error

  if hover.get.isNone:
    # Not found
    return Result[(), string].ok ()

  var hoverWin = initHoverWindow(
    currentMainWindowNode,
    hover.get.get.toHoverContent)

  # Keep the cursor position on currentMainWindowNode and display the hover
  # window on the top.
  hoverWin.overwrite(currentMainWindowNode.window.get)
  hoverWin.refresh

  # Wait until any key is pressed.
  discard getKeyBlocking()
  hoverWin.close

  return Result[(), string].ok ()

proc showLspServerLog(
  commandLine : var CommandLine,
  notify: JsonNode): Result[(), string] =
    ## Show the log to the command line.
    ## window/showMessage

    let m = parseWindowShowMessageNotify(notify)
    if m.isErr:
      return Result[(), string].err fmt"Invalid log: {m.error}"

    case m.get.messageType:
      of LspMessageType.error:
        commandLine.writeLspServerError(m.get.message)
      of LspMessageType.warn:
        commandLine.writeLspServerWarn(m.get.message)
      of LspMessageType.info:
        commandLine.writeLspServerInfo(m.get.message)
      of LspMessageType.log:
        commandLine.writeLspServerLog(m.get.message)
      of LspMessageType.debug:
        commandLine.writeLspServerDebug(m.get.message)

    return Result[(), string].ok ()

proc targetBufstatus(
  bufStatuses: seq[BufferStatus],
  absPath: string): Option[BufferStatus] {.inline.}  =
    ## Find a bufStatus with the absolute path.

    for b in bufStatuses:
      if $b.path.absolutePath == absPath: return some(b)

proc lspDiagnostics(
  bufStatuses: var seq[BufferStatus],
  notify: JsonNode): Result[(), string] =
    ## Set BufferStatus.syntaxCheckResults to diagnostics results.
    ## textDocument/publishDiagnostics

    let parseResult = parseTextDocumentPublishDiagnosticsNotify(notify)
    if parseResult.isErr:
      return Result[(), string].err fmt"lsp: Invalid diagnostics: {parseResult.error}"

    if parseResult.get.isNone:
      # Not found
      return Result[(), string].ok ()

    let diagnostics = parseResult.get.get

    var b = bufStatuses.targetBufstatus(diagnostics.path)
    if b.isNone:
      # Not found
      return Result[(), string].ok ()

    # Clear before results
    b.get.syntaxCheckResults = @[]

    for d in diagnostics.diagnostics:
      var syntaxErr = SyntaxError()
      syntaxErr.position = d.range.start.toBufferPosition
      if d.severity.isSome:
        syntaxErr.messageType = d.severity.get.toSyntaxCheckMessageType
      else:
        syntaxErr.messageType = SyntaxCheckMessageType.info
      syntaxErr.message = d.message.toRunes

      b.get.syntaxCheckResults.add syntaxErr

    return Result[(), string].ok ()

proc handleLspServerNotify(
  status: var EditorStatus,
  notify: JsonNode): Result[(), string] =
    ## Handle the notification from the server.
    ## window/showMessage, textDocument/PublishDiagnostics, etc....

    let lspMethod = notify.lspMethod
    if lspMethod.isErr:
      # Ignore.
      return Result[(), string].err fmt"Invalid server notify: {notify}"

    case lspMethod.get:
      of windowShowMessage:
        return status.commandLine.showLspServerLog(notify)
      of textDocumentPublishDiagnostics:
        return status.bufStatus.lspDiagnostics(notify)
      else:
        # Ignore
        return Result[(), string].err fmt"Not supported: {notify}"

proc handleLspResponse*(status: var EditorStatus) =
  ## Read a Json from the server and handle the response and notification.

  if not lspClient.running:
    status.commandLine.writeLspError("server crashed")
    return

  let resJson = lspClient.read
  if resJson.isErr:
    # Maybe invalid messages. Ignore.
    error fmt"lsp: Invalid message: {resJson}"
    return

  if resJson.get.isLspError:
    status.commandLine.writeLspError(resJson.error)
    return

  if resJson.get.isServerNotify:
    # The notification from the server.

    lspClient.addNotifyFromServerLog(resJson.get)

    let r = status.handleLspServerNotify(resJson.get)
    if r.isErr:
      error "lsp: {r.error}"
  else:
    # The response from the server.

    lspClient.addResponseLog(resJson.get)

    if status.isWaitingLspResponse:
      case lspClient.waitingResponse.get:
        of LspMethod.initialize:
          let r = status.lspInitialized(resJson.get)
          if r.isErr:
            status.commandLine.writeLspInitializeError(
              status.bufStatus[^1].extension,
              r.error)
        of LspMethod.textDocumentHover:
          let r = status.lspHover(resJson.get)
          if r.isErr: status.commandLine.writeLspHoverError(r.error)
        else:
          discard
    else:
      # Should ignore?
      info fmt"lsp: Ignore response: {resJson}"
      discard
