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
import editorstatus, windownode, popupwindow, unicodeext, independentutils, ui,
       gapbuffer, messages, commandline, bufferstatus, syntaxcheck, completion

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

    block:
      # textDocument/didOpen notification
      let err = lspClient.textDocumentDidOpen(
        $currentBufStatus.path.absolutePath,
        currentBufStatus.langId,
        currentBufStatus.buffer.toString)
      if err.isErr:
        return Result[(), string].err err.error

    status.commandLine.writeLspInitialized(
      status.settings.lsp.languages[currentBufStatus.langId].command)

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
    ##
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
    ##
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

proc lspProgressCreate(
  c: var LspClient,
  notify: JsonNode): Result[(), string] =
    ## Init a LSP progress.
    ##
    ## window/workDoneProgress/create

    let token = parseWindowWorkDnoneProgressCreateNotify(notify)
    if token.isErr:
      return Result[(), string].err fmt"Invalid server notify: {token.error}"

    c.createProgress(token.get)

    return Result[(), string].ok ()

proc progressMessage(p: ProgressReport): string {.inline.} =
  case p.state:
    of begin:
      if p.message.len > 0:
        return fmt"{p.title}: {p.message}"
      else:
        return p.title
    of report:
      result = fmt"{p.title}: "
      if p.percentage.isSome: result &= fmt"{$p.percentage.get}%: "
      result &= p.message
    of `end`:
      return fmt"{p.title}: {p.message}"
    else:
      return ""

proc lspProgress(
  status: var EditorStatus,
  notify: JsonNode): Result[(), string] =
    ## Begin/Report/End the LSP progress.
    ##
    ## $/progress

    let token = workDoneProgressToken(notify)

    if isWorkDoneProgressBegin(notify):
      let begin = parseWorkDoneProgressBegin(notify)
      if begin.isErr:
        return Result[(), string].err fmt"Invalid server notify: {begin.error}"

      if isCancellable(begin.get):
        # Cancel
        return lspClient.delProgress(token)

      let err = lspClient.beginProgress(token, begin.get)
      if err.isErr:
        return Result[(), string].err fmt"Invalid server notify: {err.error}"
    elif isWorkDoneProgressReport(notify):
      let report = parseWorkDoneProgressReport(notify)
      if report.isErr:
        return Result[(), string].err fmt"Invalid server notify: {report.error}"

      if isCancellable(report.get):
        # Cancel
        return lspClient.delProgress(token)

      let err = lspClient.reportProgress(token, report.get)
      if err.isErr:
        return Result[(), string].err fmt"Invalid server notify: {err.error}"
    elif isWorkDoneProgressEnd(notify):
      let `end` = parseWorkDoneProgressEnd(notify)
      if `end`.isErr:
        return Result[(), string].err fmt"Invalid server notify: {`end`.error}"

      let err = lspClient.endProgress(token, `end`.get)
      if err.isErr:
        return Result[(), string].err fmt"Invalid server notify: {err.error}"
    else:
      return Result[(), string].err fmt"Invalid server notify: {notify}"

    case lspClient.progress[token].state:
      of begin, report, `end`:
        status.commandLine.writeLspProgress(
          progressMessage(lspClient.progress[token]))
      else:
        discard

    return Result[(), string].ok ()

proc lspCompletion(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## Update the BufferStatus.completionList.
    ##
    ## textDocument/completion

    lspClient.clearWaitingResponse

    currentBufStatus.lspCompletionList.clear

    let list = res.parseTextDocumentCompletionResponse
    if list.isErr:
      return Result[(), string].err fmt"Invalid response: {list.error}"

    if list.get.len > 0:
      for item in list.get:
        var newItem = CompletionItem()

        newItem.label = item.label.toRunes

        if item.insertText.isSome:
          newItem.insertText = item.insertText.get.toRunes
        else:
          newItem.insertText = item.label.toRunes

        currentBufStatus.lspCompletionList.add newItem

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
      of windowLogMessage:
        # Already logged to LspClint.log.
        return Result[(), string].ok ()
      of workspaceConfiguration:
        # TODO: Configure settings based on notifications if necessary.
        return Result[(), string].ok ()
      of windowWorkDnoneProgressCreate:
        return lspClient.lspProgressCreate(notify)
      of progress:
        return status.lspProgress(notify)
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
    status.commandLine.writeLspError($resJson.get["error"])
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
              currentBufStatus.langId.toRunes,
              r.error)
        of LspMethod.textDocumentHover:
          let r = status.lspHover(resJson.get)
          if r.isErr: status.commandLine.writeLspHoverError(r.error)
        of LspMethod.textDocumentCompletion:
          let r = status.lspCompletion(resJson.get)
          if r.isErr: status.commandLine.writeLspCompletionError(r.error)
        else:
          discard
    else:
      # Should ignore?
      info fmt"lsp: Ignore response: {resJson}"
      discard
