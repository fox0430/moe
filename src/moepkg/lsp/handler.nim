#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[options, tables, json, logging, strformat, sequtils, strutils]

import pkg/results

import
  ../syntax/highlite,
  ../editorstatus,
  ../windownode,
  ../popupwindow,
  ../unicodeext,
  ../independentutils,
  ../ui,
  ../gapbuffer,
  ../messages,
  ../commandline,
  ../bufferstatus,
  ../syntaxcheck,
  ../completion,
  ../highlight,
  ../movement,
  ../referencesmode,
  ../fileutils,
  ../callhierarchyviewer

import client, utils, hover, message, diagnostics, semantictoken, progress,
       inlayhint, definition, typedefinition, references, rename, declaration,
       implementation, callhierarchy, documenthighlight, documentlink,
       codelens, executecommand

# Workaround for Nim 1.6.2
import completion as lspcompletion

template isLspResponse*(status: EditorStatus): bool =
  status.lspClients.contains(currentBufStatus.langId) and
  not lspClient.closed and
  (let r = lspClient.readable; r.isOk and r.get)

proc lspInitialized(
  status: var EditorStatus,
  initializeRes: JsonNode): Result[(), string] =
    ## Send notifications for initialize LSP.

    block:
      let r = lspClient.initCapacities(
        status.settings.lsp.features,
        initializeRes)
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

    block:
      # textDocument/semanticTokens
      let err = lspClient.textDocumentSemanticTokens(
        currentBufStatus.id,
        $currentBufStatus.path.absolutePath)
      if err.isErr:
        error fmt"lsp: {err.error}"

      # textDocument/inlayHint
      lspClient.sendLspInlayHintRequest(
        currentBufStatus,
        status.bufferIndexInCurrentWindow,
        mainWindowNode)

      # textDocument/codelens
      lspClient.sendLspCodeLens(currentBufStatus)

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
      absPosition = windowNode.absolutePosition
      expectPosition = Position(y: absPosition.y + 1, x: absPosition.x + 1)
    result = initPopupWindow(
      expectPosition,
      Size(h: buffer.len, w: buffer.maxLen),
      buffer)

    let
      minPosition = Position(y: windowNode.y, x: windowNode.x)
      maxPosition = Position(
        y: windowNode.y + windowNode.h,
        x: windowNode.x + windowNode.w)
    result.autoMoveAndResize(minPosition, maxPosition)
    result.update

proc lspHover*(status: var EditorStatus, res: JsonNode): Result[(), string] =
  ## Display the hover on a popup window until any key is pressed.
  ## textDocument/hover.
  ## TODO: Add tests after resolving the forever key waiting problem.

  let hover = parseTextDocumentHoverResponse(res)
  if hover.isErr:
    return Result[(), string].err hover.error

  lspClient.deleteWaitingResponse(res["id"].getInt)

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


    let list = res.parseTextDocumentCompletionResponse
    if list.isErr:
      return Result[(), string].err fmt"Invalid response: {list.error}"

    lspClient.deleteWaitingResponse(res["id"].getInt)

    currentBufStatus.lspCompletionList.clear

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

proc lspSemanticTokens(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## Update the highlight from semanticTokens.
    ##
    ## textDocument/semanticTokens

    let r = res.parseTextDocumentSemanticTokensResponse(
      lspClient.capabilities.get.semanticTokens.get)
    if r.isErr:
      return Result[(), string].err r.error

    lspClient.deleteWaitingResponse(res["id"].getInt)

    if r.get.len > 0:
      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        r.get,
        lspClient.capabilities.get.semanticTokens.get)
    else:
      let lang =
        if not status.settings.standard.syntax: SourceLanguage.langNone
        else: currentBufStatus.language
      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        lang)

    return Result[(), string].ok ()

proc lspInlayHint(status: var EditorStatus, res: JsonNode): Result[(), string] =
  ## textDocument/inlayHint

  let hints = parseTextDocumentInlayHintResponse(res)
  if hints.isErr:
    return Result[(), string].err hints.error

  let requestId =
    try: res["id"].getInt
    except CatchableError as e: return Result[(), string].err e.msg

  let waitingRes = lspClient.getWaitingResponse(requestId)
  if waitingRes.isNone:
    return Result[(), string].err fmt"Not found id: {requestId}"

  lspClient.deleteWaitingResponse(requestId)

  for i, b in status.bufStatus:
    if b.id == waitingRes.get.bufferId:
      b.inlayHints.hints = hints.get
      break

  return Result[(), string].ok ()

proc openWindowAndGotoDefinition(
  status: var EditorStatus,
  l: BufferLocation): Result[(), string] =
    ## Goto definition and Goto TypeDefinition.

    if l.path == $currentBufStatus.absolutePath:
      currentMainWindowNode.currentLine = l.range.first.line
      currentMainWindowNode.currentColumn = l.range.first.column
    else:
      # Open a buffer in a new window.
      status.verticalSplitWindow
      status.moveNextWindow

      let r = status.addNewBufferInCurrentWin(l.path)
      if r.isErr:
        return Result[(), string].err fmt"Cannot open file: {l.path}"

      status.changeCurrentBuffer(status.bufStatus.high)

      template canMove(): bool =
        l.range.first.line < currentBufStatus.buffer.len and
        l.range.first.column < currentBufStatus.buffer[l.range.first.line].len

      if not canMove():
        return Result[(), string].err fmt"Invalid position: {$l.range.first.line}, {$l.range.first.column}"

      status.resize
      status.update

      jumpLine(currentBufStatus, currentMainWindowNode, l.range.first.line)
      currentMainWindowNode.currentColumn = l.range.first.column

    return Result[(), string].ok ()

proc lspDeclaration(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## textDocument/declaration

    let parseResult = parseTextDocumentDeclaration(res)

    let requestId =
      try: res["id"].getInt
      except CatchableError as e: return Result[(), string].err e.msg
    lspClient.deleteWaitingResponse(requestId)

    if parseResult.isErr:
      return Result[(), string].err parseResult.error
    if parseResult.get.isNone:
      return Result[(), string].err fmt"Not found"

    return status.openWindowAndGotoDefinition(parseResult.get.get.location)

proc lspDefinition(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## textDocument/definition

    let parseResult = parseTextDocumentDefinition(res)

    let requestId =
      try: res["id"].getInt
      except CatchableError as e: return Result[(), string].err e.msg
    lspClient.deleteWaitingResponse(requestId)

    if parseResult.isErr:
      return Result[(), string].err parseResult.error
    if parseResult.get.isNone:
      return Result[(), string].err fmt"Not found"

    return status.openWindowAndGotoDefinition(parseResult.get.get.location)

proc lspTypeDefinition(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## textDocument/typeDefinition

    let parseResult = parseTextDocumentTypeDefinition(res)

    let requestId =
      try: res["id"].getInt
      except CatchableError as e: return Result[(), string].err e.msg
    lspClient.deleteWaitingResponse(requestId)

    if parseResult.isErr:
      return Result[(), string].err parseResult.error
    if parseResult.get.isNone:
      return Result[(), string].err fmt"Not found"

    return status.openWindowAndGotoDefinition(parseResult.get.get.location)

proc lspImplementation(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## textDocument/implementation

    let parseResult = parseTextDocumentImplementation(res)

    let requestId =
      try: res["id"].getInt
      except CatchableError as e: return Result[(), string].err e.msg
    lspClient.deleteWaitingResponse(requestId)

    if parseResult.isErr:
      return Result[(), string].err parseResult.error
    if parseResult.get.isNone:
      return Result[(), string].err fmt"Not found"

    return status.openWindowAndGotoDefinition(parseResult.get.get.location)

proc lspReferences(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## textDocument/references
    ## Open a references mode window.

    let parseResult = parseTextDocumentReferencesResponse(res)

    let requestId =
      try: res["id"].getInt
      except CatchableError as e: return Result[(), string].err e.msg
    lspClient.deleteWaitingResponse(requestId)

    if parseResult.isErr:
      return Result[(), string].err parseResult.error
    elif parseResult.get.len == 0:
      return Result[(), string].err "References not found"

    # Open a new window with references mode.
    status.horizontalSplitWindow
    status.moveNextWindow

    discard status.addNewBufferInCurrentWin(Mode.references)
    currentBufStatus.buffer = initReferencesModeBuffer(parseResult.get)
      .toGapBuffer

    status.resize

    return Result[(), string].ok ()

proc getBufferIndexByAbsPath(status: EditorStatus, path: Runes): Option[int] =
  for i, b in status.bufStatus:
    if b.absolutePath == path:
      return some(i)

proc lspRename(status: var EditorStatus, res: JsonNode): Result[(), string] =
  ## textDocument/rename

  let lspRenames = parseTextDocumentRenameResponse(res)

  try:
    lspClient.deleteWaitingResponse(res["id"].getInt)
  except CatchableError as e:
    return Result[(), string].err e.msg

  if lspRenames.isErr:
    return Result[(), string].err lspRenames.error

  if lspRenames.get.len == 0:
    return Result[(), string].err "Not found"

  for r in lspRenames.get:
    let bufIndex = status.getBufferIndexByAbsPath(r.path.toRunes)
    if bufIndex.isSome:
      template b: BufferStatus = status.bufStatus[bufIndex.get]

      for c in r.changes:
        if c.range.first.line > b.buffer.high or
           c.range.last.column > b.buffer[c.range.first.line].high:
             return Result[(), string].err fmt"lsp rename: invalid range: {r.path}: {$c.range}"

        var newLine = b.buffer[c.range.first.line]
        for _ in 0 ..< c.range.last.column - c.range.first.column:
          newLine.delete c.range.first.column
        newLine.insert(c.text.toRunes, c.range.first.column)

        b.buffer[c.range.first.line] = newLine
    else:
      let file = openFile(r.path)
      if file.isErr:
        return Result[(), string].err fmt"lsp rename: cannot open: {r.path}: {file.error}"

      var lines = file.get.text.splitLines
      for c in r.changes:
        if c.range.first.line > lines.high or
           c.range.last.column > lines[c.range.first.line].high:
             return Result[(), string].err fmt"lsp rename: invalid range: {r.path}: {$c.range}"

        lines[c.range.first.line].delete(c.range.first.column .. c.range.last.column)
        lines[c.range.first.line].insert(c.text.toRunes, c.range.first.column)

      let err = saveFile(r.path, lines.toRunes, file.get.encoding)
      if err.isErr:
        return Result[(), string].err fmt"lsp rename: cannot write: {r.path}: {file.error}"

    info fmt"lsp rename success: {r.path}"

  return Result[(), string].ok ()

proc lspPrepareCallHierarchy(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## textDocument/prepareCallHierarchy

    let items = parseTextDocumentPrepareCallHierarchyResponse(res)

    try:
      lspClient.deleteWaitingResponse(res["id"].getInt)
    except CatchableError as e:
      return Result[(), string].err e.msg

    if items.isErr:
      return Result[(), string].err items.error

    if items.get.len == 0:
      return Result[(), string].err "Not found"

    let langId = currentBufStatus.langId

    # Open a new window with callhierarchy viewer.
    status.verticalSplitWindow
    status.moveNextWindow

    discard status.addNewBufferInCurrentWin(Mode.callhierarchyviewer)
    let buf = initCallHierarchyViewBuffer(
      CallHierarchyType.prepare,
      items.get)
    if buf.isErr:
      return Result[(), string].err buf.error

    currentBufStatus.buffer = buf.get.toGapBuffer
    currentBufStatus.langId = langId
    currentBufStatus.callHierarchyInfo.items = items.get

    currentMainWindowNode.currentLine = CallHierarchyViewHeaderLength

    status.resize

    return Result[(), string].ok ()

proc lspIncomingCalls(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## callHierarchy/incomingCalls

    let calls = parseCallhierarchyIncomingCallsResponse(res)

    try:
      lspClient.deleteWaitingResponse(res["id"].getInt)
    except CatchableError as e:
      return Result[(), string].err e.msg

    if calls.isErr:
      return Result[(), string].err calls.error

    if calls.get.len == 0:
      return Result[(), string].err "Not found"

    let items = calls.get.mapIt(it.`from`)

    let buf = initCallHierarchyViewBuffer(
      CallHierarchyType.incoming,
      items)
    if buf.isErr:
      return Result[(), string].err buf.error

    currentBufStatus.buffer = buf.get.toGapBuffer
    currentBufStatus.callHierarchyInfo.items = items
    currentBufStatus.isUpdate = true

    currentMainWindowNode.currentLine = CallHierarchyViewHeaderLength

    status.update

    return Result[(), string].ok ()

proc lspOutgoingCalls(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## callHierarchy/outgoingCalls

    try:
      lspClient.deleteWaitingResponse(res["id"].getInt)
    except CatchableError as e:
      return Result[(), string].err e.msg

    let calls =
      # Workaround for "Error: generic instantiation too nested"
      try:
        parseCallhierarchyOutgoingCallsResponse(res).get
      except ResultDefect as e:
        return Result[(), string].err e.msg

    if calls.len == 0:
      return Result[(), string].err "Not found"

    let items = calls.mapIt(it.`to`)

    let buf = initCallHierarchyViewBuffer(
      CallHierarchyType.outgoing,
      items)
    if buf.isErr:
      return Result[(), string].err buf.error

    currentBufStatus.buffer = buf.get.toGapBuffer
    currentBufStatus.callHierarchyInfo.items = items
    currentBufStatus.isUpdate = true

    currentMainWindowNode.currentLine = CallHierarchyViewHeaderLength

    status.update

    return Result[(), string].ok ()

proc lspDocumentHighlight(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## textDocument/documentHighlight

    try:
      lspClient.deleteWaitingResponse(res["id"].getInt)
    except CatchableError as e:
      return Result[(), string].err e.msg

    currentBufStatus.documentHighlightInfo.ranges =
      # Workaround for "Error: generic instantiation too nested"
      try:
        parseDocumentHighlightResponse(res).get
      except ResultDefect as e:
        return Result[(), string].err e.msg

    return Result[(), string].ok ()

proc lspDocumentLink(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## textDocument/documentLink

    try:
      lspClient.deleteWaitingResponse(res["id"].getInt)
    except CatchableError as e:
      return Result[(), string].err e.msg

    let links =
      # Workaround for "Error: generic instantiation too nested"
      try:
        parseDocumentLinkResponse(res).get
      except ResultDefect as e:
        return Result[(), string].err e.msg

    if links.len == 0:
      return Result[(), string].err "Not found"

    if links[0].isResolve:
      let r = lspClient.documentLinkResolve(currentBufStatus.id, links[0])
      if r.isErr:
        return Result[(), string].err r.error

    return Result[(), string].ok ()

proc lspDocumentLinkResolve(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## documentLink/resolve

    try:
      lspClient.deleteWaitingResponse(res["id"].getInt)
    except CatchableError as e:
      return Result[(), string].err e.msg

    let link =
      # Workaround for "Error: generic instantiation too nested"
      try:
        parseDocumentLinkResolveResponse(res).get
      except ResultDefect as e:
        return Result[(), string].err e.msg

    if link.target.isNone:
      return Result[(), string].err "Not found target"

    let path = link.target.get.uriToPath
    if path.isErr:
      return Result[(), string].err path.error

    return status.openWindowAndGotoDefinition(
      BufferLocation(path: path.get))

proc lspCodeLens(status: var EditorStatus, res: JsonNode): Result[(), string] =
  ## textDocument/codeLens

  let requestId =
    try: res["id"].getInt
    except CatchableError as e: return Result[(), string].err e.msg

  let waitingRes = lspClient.getWaitingResponse(requestId)
  if waitingRes.isNone:
    return Result[(), string].err fmt"Not found id: {requestId}"

  lspClient.deleteWaitingResponse(res["id"].getInt)

  let r =
    # Workaround for "Error: generic instantiation too nested"
    try:
      parseCodeLensResponse(res).get
    except ResultDefect as e:
      return Result[(), string].err e.msg

  for b in status.bufStatus:
    if b.id == waitingRes.get.bufferId:
      b.codeLenses = r

  return Result[(), string].ok ()

proc lspCodeLensResolve(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## codeLens/resolve

    let requestId =
      try: res["id"].getInt
      except CatchableError as e: return Result[(), string].err e.msg

    let waitingRes = lspClient.getWaitingResponse(requestId)
    if waitingRes.isNone:
      return Result[(), string].err fmt"Not found id: {requestId}"

    lspClient.deleteWaitingResponse(res["id"].getInt)

    let _ =
      # Workaround for "Error: generic instantiation too nested"
      try:
        parseCodeLensResolveResponse(res).get
      except ResultDefect as e:
        return Result[(), string].err e.msg

    # TODO: Run commands?

    return Result[(), string].ok ()

proc lspExecuteCommand(
  status: var EditorStatus,
  res: JsonNode): Result[(), string] =
    ## workspace/executeCommand

    try:
      lspClient.deleteWaitingResponse(res["id"].getInt)
    except CatchableError as e:
      return Result[(), string].err e.msg

    # Workaround for "Error: generic instantiation too nested"
    try:
      # TODO: Handle Execute command response.
      discard parseExecuteCommandResponse(res).get
    except ResultDefect as e:
      return Result[(), string].err e.msg

    return Result[(), string].ok ()

proc handleLspServerRequest(
  status: var EditorStatus,
  req: JsonNode): Result[(), string] =
    ## Handle the request from the server.
    ## workspace/inlayHint/refresh, etc....

    let lspMethod = req.lspMethod
    if lspMethod.isErr:
      # Ignore.
      return Result[(), string].err fmt"Invalid server request: {req}"

    template isReady(status: EditorStatus): bool =
      currentBufStatus.langId.len > 0 and
      status.lspClients.contains(currentBufStatus.langId) and
      lspClient.isInitialized

    case lspMethod.get:
      of LspMethod.workspaceCodeLensRefresh:
        if status.isReady:
          lspClient.sendLspCodeLens(currentBufStatus)
      of LspMethod.workspaceSemanticTokensRefresh:
        if status.isReady:
          lspClient.sendLspSemanticTokenRequest(currentBufStatus)
      of LspMethod.workspaceInlayHintRefresh:
        if status.isReady:
          lspClient.sendLspInlayHintRequest(
            currentBufStatus,
            status.bufferIndexInCurrentWindow,
            mainWindowNode)
      else:
        # Ignore
        return Result[(), string].err fmt"Not supported: {req}"

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
      of LspMethod.windowShowMessage:
        return status.commandLine.showLspServerLog(notify)
      of LspMethod.windowLogMessage:
        # Already logged to LspClint.log.
        return Result[(), string].ok ()
      of LspMethod.workspaceConfiguration:
        # TODO: Configure settings based on notifications if necessary.
        return Result[(), string].ok ()
      of LspMethod.windowWorkDnoneProgressCreate:
        return lspClient.lspProgressCreate(notify)
      of LspMethod.progress:
        return status.lspProgress(notify)
      of LspMethod.textDocumentPublishDiagnostics:
        return status.bufStatus.lspDiagnostics(notify)
      else:
        # Ignore
        return Result[(), string].err fmt"Not supported: {notify}"

proc containsBufferId(
  bufStatuses: seq[BufferStatus],
  bufferId: int): bool {.inline.} =

    for b in bufStatuses:
      if b.id == bufferId: return true

proc handleLspResponse*(status: var EditorStatus) =
  ## Read a Json from the server and handle the response and notification.

  while status.isLspResponse:
    if not lspClient.closed and not lspClient.running:
      lspClient.closed = true
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

    if resJson.get.isRequest:
      # The request from the server.

      lspClient.addRequestLog(resJson.get)

      let r = status.handleLspServerRequest(resJson.get)
      if r.isErr:
        error "lsp: {r.error}"
    elif resJson.get.isNotify:
      # The notification from the server.

      lspClient.addNotifyFromServerLog(resJson.get)

      let r = status.handleLspServerNotify(resJson.get)
      if r.isErr:
        error "lsp: {r.error}"
    else:
      # The response from the server.

      lspClient.addResponseLog(resJson.get)

      let requestId =
        try:
          resJson.get["id"].getInt.RequestId
        except CatchableError:
          error fmt"lsp: Not found request id: {resJson.get}"
          return

      if requestId > lspClient.lastId:
        lspClient.lastId = requestId

      let waitingResponse = lspClient.getWaitingResponse(requestId)
      if waitingResponse.isNone:
        error fmt"lsp: Not found request id: {resJson.get}"
        return

      if not status.bufStatus.containsBufferId(waitingResponse.get.bufferId):
        info fmt"lsp: closed buffer. bufferId: {$waitingResponse.get.bufferId}"
        return

      case waitingResponse.get.lspMethod:
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
        of LspMethod.textDocumentSemanticTokensFull:
          let r = status.lspSemanticTokens(resJson.get)
          if r.isErr: status.commandLine.writeLspSemanticTokensError(r.error)
        of LspMethod.textDocumentInlayHint:
          let r = status.lspInlayHint(resJson.get)
          if r.isErr: status.commandLine.writeLspInlayHintError(r.error)
        of LspMethod.textDocumentDeclaration:
          let r = status.lspDeclaration(resJson.get)
          if r.isErr: status.commandLine.writeLspDeclarationError(r.error)
        of LspMethod.textDocumentDefinition:
          let r = status.lspDefinition(resJson.get)
          if r.isErr: status.commandLine.writeLspDefinitionError(r.error)
        of LspMethod.textDocumentTypeDefinition:
          let r = status.lspTypeDefinition(resJson.get)
          if r.isErr: status.commandLine.writeLspTypeDefinitionError(r.error)
        of LspMethod.textDocumentImplementation:
          let r = status.lspImplementation(resJson.get)
          if r.isErr: status.commandLine.writeLspImplementationError(r.error)
        of LspMethod.textDocumentReferences:
          let r = status.lspReferences(resJson.get)
          if r.isErr: status.commandLine.writeLspReferencesError(r.error)
        of LspMethod.textDocumentRename:
          let r = status.lspRename(resJson.get)
          if r.isErr: status.commandLine.writeLspRenameError(r.error)
        of LspMethod.textDocumentPrepareCallHierarchy:
          let r = status.lspPrepareCallHierarchy(resJson.get)
          if r.isErr: status.commandLine.writeLspCallHierarchyError(r.error)
        of LspMethod.callHierarchyIncomingCalls:
          let r = status.lspIncomingCalls(resJson.get)
          if r.isErr: status.commandLine.writeLspCallHierarchyError(r.error)
        of LspMethod.callHierarchyOutgoingCalls:
          let r = status.lspOutgoingCalls(resJson.get)
          if r.isErr: status.commandLine.writeLspCallHierarchyError(r.error)
        of LspMethod.textDocumentDocumentHighlight:
          let r = status.lspDocumentHighlight(resJson.get)
          if r.isErr: status.commandLine.writeLspDocumentHighlightError(r.error)
        of LspMethod.textDocumentDocumentLink:
          let r = status.lspDocumentLink(resJson.get)
          if r.isErr: status.commandLine.writeLspDocumentLinkError(r.error)
        of LspMethod.documentLinkResolve:
          let r = status.lspDocumentLinkResolve(resJson.get)
          if r.isErr: status.commandLine.writeLspDocumentLinkError(r.error)
        of LspMethod.textDocumentCodeLens:
          let r = status.lspCodeLens(resJson.get)
          if r.isErr: status.commandLine.writeLspCodeLensError(r.error)
        of LspMethod.codeLensResolve:
          let r = status.lspCodeLensResolve(resJson.get)
          if r.isErr: status.commandLine.writeLspCodeLensError(r.error)
        of LspMethod.workspaceExecuteCommand:
          let r = status.lspExecuteCommand(resJson.get)
          if r.isErr: status.commandLine.writeLspExecuteCommandError(r.error)
        else:
          info fmt"lsp: Ignore response: {resJson}"
