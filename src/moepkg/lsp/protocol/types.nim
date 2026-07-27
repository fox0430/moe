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

## LSP Protocol Types
## Based on LSP Specification 3.17

import std/[options, json, tables]

import pkg/jsony

import enums

export enums

type
  # Basic types
  Position* = object
    ## Position in a text document (0-indexed)
    ## Note: character is in UTF-16 code units
    line*: int
    character*: int

  Range* = object ## A range in a text document
    start*: Position
    `end`*: Position

  Location* = object ## Represents a location inside a resource
    uri*: string
    range*: Range

  LocationLink* = object ## A link to a location
    originSelectionRange*: Option[Range]
    targetUri*: string
    targetRange*: Range
    targetSelectionRange*: Range

  # Text document types
  TextDocumentIdentifier* = object ## Identifies a text document
    uri*: string

  VersionedTextDocumentIdentifier* = object ## Identifies a text document with version
    uri*: string
    version*: int

  TextDocumentItem* = object ## An item to transfer a text document
    uri*: string
    languageId*: string
    version*: int
    text*: string

  TextDocumentPositionParams* = object ## Parameters for text document position requests
    textDocument*: TextDocumentIdentifier
    position*: Position

  TextEdit* = object ## A text edit
    range*: Range
    newText*: string

  OptionalVersionedTextDocumentIdentifier* = object
    ## Text document identifier with optional version
    uri*: string
    version*: Option[int]
      # null means the version is known and the content on disk is the truth

  TextDocumentEdit* = object ## An edit to a versioned text document
    textDocument*: OptionalVersionedTextDocumentIdentifier
    edits*: seq[TextEdit]

  WorkspaceEdit* = object ## A workspace edit
    changes*: Option[Table[string, seq[TextEdit]]] # uri -> edits
    documentChanges*: Option[seq[TextDocumentEdit]]
    resourceOperations*: seq[string]
      ## "kind" of any create/rename/delete file operations present in
      ## documentChanges. moe does not apply file operations; this records
      ## that they were requested so callers can refuse rather than apply a
      ## partial edit.

  TextDocumentContentChangeEvent* = object ## Content change event for didChange
    range*: Option[Range]
    rangeLength*: Option[int]
    text*: string

  # Diagnostic types
  DiagnosticRelatedInformation* = object ## Related information for a diagnostic
    location*: Location
    message*: string

  Diagnostic* = object ## A diagnostic (error, warning, etc.)
    range*: Range
    severity*: Option[DiagnosticSeverity]
    code*: Option[JsonNode]
    codeDescription*: Option[JsonNode]
    source*: Option[string]
    message*: string
    tags*: Option[seq[DiagnosticTag]]
    relatedInformation*: Option[seq[DiagnosticRelatedInformation]]
    data*: Option[JsonNode]

  PublishDiagnosticsParams* = object ## Parameters for publishDiagnostics notification
    uri*: string
    version*: Option[int]
    diagnostics*: seq[Diagnostic]

  # Completion types
  CompletionContext* = object ## Additional information about completion context
    triggerKind*: CompletionTriggerKind
    triggerCharacter*: Option[string]

  CompletionParams* = object ## Parameters for completion request
    textDocument*: TextDocumentIdentifier
    position*: Position
    context*: Option[CompletionContext]

  MarkupContent* = object ## Markup content for documentation
    kind*: MarkupKind
    value*: string

  CompletionItem* = object ## A completion item
    label*: string
    labelDetails*: Option[JsonNode]
    kind*: Option[CompletionItemKind]
    tags*: Option[seq[int]]
    detail*: Option[string]
    documentation*: Option[JsonNode] # string | MarkupContent
    deprecated*: Option[bool]
    preselect*: Option[bool]
    sortText*: Option[string]
    filterText*: Option[string]
    insertText*: Option[string]
    insertTextFormat*: Option[InsertTextFormat]
    insertTextMode*: Option[int]
    textEdit*: Option[JsonNode] # TextEdit | InsertReplaceEdit
    textEditText*: Option[string]
    additionalTextEdits*: Option[seq[TextEdit]]
    commitCharacters*: Option[seq[string]]
    command*: Option[JsonNode]
    data*: Option[JsonNode]

  CompletionList* = object ## Represents a collection of completion items
    isIncomplete*: bool
    itemDefaults*: Option[JsonNode]
    items*: seq[CompletionItem]

  # Hover types
  Hover* = object ## Result of a hover request
    contents*: JsonNode # MarkedString | MarkedString[] | MarkupContent
    range*: Option[Range]

  HoverParams* = object ## Parameters for hover request
    textDocument*: TextDocumentIdentifier
    position*: Position

  # Signature Help types
  ParameterInformation* = object ## Information about a parameter
    label*: string # Parameter label as substring form
    labelOffsets*: Option[tuple[start, stop: int]]
      # [start, end) offsets into the signature label
    documentation*: Option[JsonNode] # string | MarkupContent

  SignatureInformation* = object ## Information about a signature
    label*: string
    documentation*: Option[JsonNode] # string | MarkupContent
    parameters*: Option[seq[ParameterInformation]]
    activeParameter*: Option[int]

  SignatureHelp* = object ## Result of signature help request
    signatures*: seq[SignatureInformation]
    activeSignature*: Option[int]
    activeParameter*: Option[int]

  SignatureHelpParams* = object ## Parameters for signature help request
    textDocument*: TextDocumentIdentifier
    position*: Position
    context*: Option[JsonNode] # SignatureHelpContext

  # Execute Command types
  ExecuteCommandParams* = object ## Parameters for workspace/executeCommand request
    command*: string
    arguments*: Option[seq[JsonNode]]

  ExecuteCommandOptions* = object ## Execute command options
    commands*: seq[string]
    workDoneProgress*: Option[bool]

  # Definition/Declaration types
  DefinitionParams* = object ## Parameters for definition request
    textDocument*: TextDocumentIdentifier
    position*: Position

  DeclarationParams* = object ## Parameters for declaration request
    textDocument*: TextDocumentIdentifier
    position*: Position

  # References types
  ReferenceContext* = object ## Context for find references
    includeDeclaration*: bool

  ReferenceParams* = object ## Parameters for references request
    textDocument*: TextDocumentIdentifier
    position*: Position
    context*: ReferenceContext

  # Document symbol types
  DocumentSymbol* = object ## Document symbol (hierarchical)
    name*: string
    detail*: Option[string]
    kind*: SymbolKind
    tags*: Option[seq[int]]
    deprecated*: Option[bool]
    range*: Range
    selectionRange*: Range
    children*: Option[seq[DocumentSymbol]]

  SymbolInformation* = object ## Symbol information (flat)
    name*: string
    kind*: SymbolKind
    tags*: Option[seq[int]]
    deprecated*: Option[bool]
    location*: Location
    containerName*: Option[string]

  DocumentSymbolParams* = object ## Parameters for document symbol request
    textDocument*: TextDocumentIdentifier

  DocumentSymbolResult* = object
    ## Result of documentSymbol request
    ## Either hierarchical DocumentSymbol[] or flat SymbolInformation[]
    case isHierarchical*: bool
    of true:
      symbols*: seq[DocumentSymbol]
    of false:
      symbolInfos*: seq[SymbolInformation]

  # Inlay Hint types
  InlayHintLabelPart* = object ## A part of an inlay hint label
    value*: string
    tooltip*: Option[JsonNode] # string | MarkupContent
    location*: Option[Location]
    command*: Option[JsonNode]

  InlayHint* = object ## An inlay hint
    position*: Position
    label*: JsonNode # string | InlayHintLabelPart[]
    kind*: Option[InlayHintKind]
    textEdits*: Option[seq[TextEdit]]
    tooltip*: Option[JsonNode] # string | MarkupContent
    paddingLeft*: Option[bool]
    paddingRight*: Option[bool]
    data*: Option[JsonNode]

  InlayHintParams* = object ## Parameters for inlay hint request
    textDocument*: TextDocumentIdentifier
    range*: Range

  # Selection Range types
  SelectionRange* = ref object ## Selection range with optional parent
    range*: Range
    parent*: SelectionRange # nil if no parent

  SelectionRangeParams* = object ## Parameters for selection range request
    textDocument*: TextDocumentIdentifier
    positions*: seq[Position]

  # Document Highlight types
  DocumentHighlight* = object
    ## A document highlight is a range inside a text document which deserves
    ## special attention. Usually a document highlight is visualized by changing
    ## the background color of its range.
    range*: Range
    kind*: Option[DocumentHighlightKind]

  DocumentHighlightParams* = object ## Parameters for document highlight request
    textDocument*: TextDocumentIdentifier
    position*: Position

  # Document Link types
  DocumentLink* = object
    ## A document link is a range in a text document that links to an internal
    ## or external resource, like another text document or a web site.
    range*: Range ## The range this link applies to
    target*: Option[string] ## The uri this link points to (can be resolved later)
    tooltip*: Option[string] ## The tooltip text when hovering over this link
    data*: Option[JsonNode] ## A data entry field for resolve request

  DocumentLinkParams* = object ## Parameters for document link request
    textDocument*: TextDocumentIdentifier

  # Command type (used by CodeLens and other features)
  Command* = object ## Represents a reference to a command
    title*: string ## Title of the command (displayed in UI)
    command*: string ## The identifier of the actual command handler
    arguments*: Option[seq[JsonNode]]
      ## Arguments that the command handler should be invoked with

  # CodeLens types
  CodeLens* = object
    ## A code lens represents a command that should be shown along with source text
    range*: Range ## The range in which this code lens is valid
    command*: Option[Command]
      ## The command this code lens represents (can be resolved later)
    data*: Option[JsonNode]
      ## A data entry field preserved on a code lens item between resolve request

  CodeLensParams* = object ## Parameters for textDocument/codeLens request
    textDocument*: TextDocumentIdentifier

  # Code Action types
  CodeActionContext* = object ## Context for code action requests
    diagnostics*: seq[Diagnostic] ## Diagnostics known to the client
    only*: Option[seq[string]]
      ## Requested kinds of actions (e.g., ["quickfix", "refactor"])
    triggerKind*: Option[int]
      ## How the code action was triggered (1=Invoked, 2=Automatic)

  CodeActionParams* = object ## Parameters for textDocument/codeAction request
    textDocument*: TextDocumentIdentifier
    range*: Range ## The range for which the command was invoked
    context*: CodeActionContext ## Context carrying additional information

  CodeAction* = object
    ## A code action represents a change that can be performed in code.
    ## Can be a simple Command, or provide edits directly.
    title*: string ## A short, human-readable title for this code action
    kind*: Option[string] ## The kind of the code action (e.g., "quickfix", "refactor")
    diagnostics*: Option[seq[Diagnostic]] ## Diagnostics this action resolves
    isPreferred*: Option[bool]
      ## Marks this as preferred action (shown in UI without submenu)
    disabled*: Option[JsonNode] ## Marks the action as disabled with a reason
    edit*: Option[WorkspaceEdit] ## The workspace edit this code action performs
    command*: Option[Command] ## A command this code action executes
    data*: Option[JsonNode] ## Data preserved between request and resolve

  # Call Hierarchy types
  CallHierarchyItem* = object
    ## Represents programming constructs like functions or constructors in the
    ## context of call hierarchy.
    name*: string ## The name of this item
    kind*: SymbolKind ## The kind of this item
    tags*: Option[seq[int]] ## Tags for this item (e.g., deprecated)
    detail*: Option[string] ## More detail for this item (e.g., signature)
    uri*: string ## The resource identifier of this item
    range*: Range ## Range enclosing this symbol (including leading/trailing whitespace)
    selectionRange*: Range ## Range that should be selected and revealed
    data*: Option[JsonNode] ## Data preserved between prepare and incoming/outgoing calls

  CallHierarchyIncomingCall* = object
    ## Represents an incoming call, e.g., a caller of a method or constructor.
    `from`*: CallHierarchyItem ## The item that makes the call
    fromRanges*: seq[Range] ## The ranges at which the calls appear

  CallHierarchyOutgoingCall* = object
    ## Represents an outgoing call, e.g., calling a getter from a method.
    to*: CallHierarchyItem ## The item that is called
    fromRanges*: seq[Range] ## The range at which this item is called

  CallHierarchyPrepareParams* = object
    ## Parameters for textDocument/prepareCallHierarchy
    textDocument*: TextDocumentIdentifier
    position*: Position

  CallHierarchyIncomingCallsParams* = object
    ## Parameters for callHierarchy/incomingCalls
    item*: CallHierarchyItem

  CallHierarchyOutgoingCallsParams* = object
    ## Parameters for callHierarchy/outgoingCalls
    item*: CallHierarchyItem

  # Folding Range types
  FoldingRange* = object ## Represents a folding range in a text document
    startLine*: int ## Zero-based line number of the start of the range
    startCharacter*: Option[int] ## Zero-based character offset of the start (optional)
    endLine*: int ## Zero-based line number of the end of the range
    endCharacter*: Option[int] ## Zero-based character offset of the end (optional)
    kind*: Option[FoldingRangeKind] ## The kind of the folding range
    collapsedText*: Option[string] ## Text to display when collapsed (LSP 3.17+)

  # Semantic Tokens types
  SemanticTokensLegend* = object
    ## Semantic tokens legend (defines token types and modifiers)
    tokenTypes*: seq[string]
    tokenModifiers*: seq[string]

  SemanticTokensOptions* = object ## Server semantic tokens options
    legend*: SemanticTokensLegend
    range*: Option[JsonNode] # bool | {}
    full*: Option[JsonNode] # bool | { delta?: bool }

  # Work Done Progress types
  WorkDoneProgressKind* = enum
    ## The kind of work done progress
    wdpkBegin = "begin"
    wdpkReport = "report"
    wdpkEnd = "end"

  WorkDoneProgressBegin* = object
    ## To start progress reporting a $/progress notification must be sent
    title*: string ## Mandatory title of the progress operation
    cancellable*: Option[bool] ## Controls if a cancel button should show
    message*: Option[string] ## Optional, more detailed progress message
    percentage*: Option[int] ## Optional progress percentage (0-100)

  WorkDoneProgressReport* = object ## Reporting progress is done using this payload
    cancellable*: Option[bool] ## Controls if a cancel button should show
    message*: Option[string] ## Optional, more detailed progress message
    percentage*: Option[int] ## Optional progress percentage (0-100)

  WorkDoneProgressEnd* = object ## Signaling the end of a progress reporting
    message*: Option[string] ## Optional final message indicating the outcome

  WorkDoneProgress* = object ## Work done progress value (discriminated union)
    case kind*: WorkDoneProgressKind
    of wdpkBegin:
      begin*: WorkDoneProgressBegin
    of wdpkReport:
      report*: WorkDoneProgressReport
    of wdpkEnd:
      `end`*: WorkDoneProgressEnd

  WorkDoneProgressParams* = object ## Parameters for $/progress notification
    token*: JsonNode ## The progress token (int | string)
    value*: WorkDoneProgress ## The progress data

  # Server capabilities
  CompletionOptions* = object ## Completion options
    triggerCharacters*: Option[seq[string]]
    allCommitCharacters*: Option[seq[string]]
    resolveProvider*: Option[bool]
    workDoneProgress*: Option[bool]

  SignatureHelpOptions* = object ## Signature help options
    triggerCharacters*: Option[seq[string]]
    retriggerCharacters*: Option[seq[string]]

  TextDocumentSyncOptions* = object ## Text document sync options
    openClose*: Option[bool]
    change*: Option[TextDocumentSyncKind]
    willSave*: Option[bool]
    willSaveWaitUntil*: Option[bool]
    save*: Option[JsonNode] # bool | SaveOptions

  ServerCapabilities* = object ## Server capabilities
    positionEncoding*: Option[string]
    textDocumentSync*: Option[JsonNode] # TextDocumentSyncOptions | TextDocumentSyncKind
    completionProvider*: Option[CompletionOptions]
    hoverProvider*: Option[JsonNode] # bool | HoverOptions
    signatureHelpProvider*: Option[SignatureHelpOptions]
    declarationProvider*: Option[JsonNode]
    definitionProvider*: Option[JsonNode]
    typeDefinitionProvider*: Option[JsonNode]
    implementationProvider*: Option[JsonNode]
    referencesProvider*: Option[JsonNode]
    documentHighlightProvider*: Option[JsonNode]
    documentSymbolProvider*: Option[JsonNode]
    codeActionProvider*: Option[JsonNode]
    codeLensProvider*: Option[JsonNode]
    documentLinkProvider*: Option[JsonNode]
    colorProvider*: Option[JsonNode]
    documentFormattingProvider*: Option[JsonNode]
    documentRangeFormattingProvider*: Option[JsonNode]
    documentOnTypeFormattingProvider*: Option[JsonNode]
    renameProvider*: Option[JsonNode]
    foldingRangeProvider*: Option[JsonNode]
    executeCommandProvider*: Option[ExecuteCommandOptions]
    selectionRangeProvider*: Option[JsonNode]
    linkedEditingRangeProvider*: Option[JsonNode]
    callHierarchyProvider*: Option[JsonNode]
    semanticTokensProvider*: Option[SemanticTokensOptions]
    monikerProvider*: Option[JsonNode]
    typeHierarchyProvider*: Option[JsonNode]
    inlayHintProvider*: Option[JsonNode]
    diagnosticProvider*: Option[JsonNode]
    workspaceSymbolProvider*: Option[JsonNode]
    workspace*: Option[JsonNode]
    experimental*: Option[JsonNode]

  # Initialize types
  ClientInfo* = object ## Information about the client
    name*: string
    version*: Option[string]

  InitializeParams* = object ## Parameters for initialize request
    processId*: Option[int]
    clientInfo*: Option[ClientInfo]
    locale*: Option[string]
    rootPath*: Option[string]
    rootUri*: Option[string]
    initializationOptions*: Option[JsonNode]
    capabilities*: JsonNode # ClientCapabilities
    trace*: Option[string]
    workspaceFolders*: Option[seq[JsonNode]]

  ServerInfo* = object ## Information about the server
    name*: string
    version*: Option[string]

  InitializeResult* = object ## Result of initialize request
    capabilities*: ServerCapabilities
    serverInfo*: Option[ServerInfo]

  # Window message types
  ShowMessageParams* = object ## Parameters for window/showMessage
    `type`*: MessageType
    message*: string

  LogMessageParams* = object ## Parameters for window/logMessage
    `type`*: MessageType
    message*: string

# Helper constructors
proc newPosition*(line, character: int): Position =
  Position(line: line, character: character)

proc newRange*(startLine, startChar, endLine, endChar: int): Range =
  Range(start: newPosition(startLine, startChar), `end`: newPosition(endLine, endChar))

proc newRange*(start, `end`: Position): Range =
  Range(start: start, `end`: `end`)

proc newTextDocumentIdentifier*(uri: string): TextDocumentIdentifier =
  TextDocumentIdentifier(uri: uri)

proc newVersionedTextDocumentIdentifier*(
    uri: string, version: int
): VersionedTextDocumentIdentifier =
  VersionedTextDocumentIdentifier(uri: uri, version: version)

proc newTextDocumentItem*(
    uri, languageId: string, version: int, text: string
): TextDocumentItem =
  TextDocumentItem(uri: uri, languageId: languageId, version: version, text: text)

# JSON serialization helpers
proc toJson*(pos: Position): JsonNode =
  %*{"line": pos.line, "character": pos.character}

proc toJson*(r: Range): JsonNode =
  %*{"start": r.start.toJson, "end": r.`end`.toJson}

proc toJson*(loc: Location): JsonNode =
  %*{"uri": loc.uri, "range": loc.range.toJson}

proc toJson*(tdi: TextDocumentIdentifier): JsonNode =
  %*{"uri": tdi.uri}

proc toJson*(vtdi: VersionedTextDocumentIdentifier): JsonNode =
  %*{"uri": vtdi.uri, "version": vtdi.version}

proc toJson*(item: TextDocumentItem): JsonNode =
  %*{
    "uri": item.uri,
    "languageId": item.languageId,
    "version": item.version,
    "text": item.text,
  }

proc toJson*(params: SelectionRangeParams): JsonNode =
  var positionsJson = newJArray()
  for pos in params.positions:
    positionsJson.add(pos.toJson)
  %*{"textDocument": params.textDocument.toJson, "positions": positionsJson}

proc toJson*(link: DocumentLink): JsonNode =
  ## Serialize DocumentLink to JSON (for resolve request)
  result = %*{"range": link.range.toJson}
  if link.target.isSome:
    result["target"] = %link.target.get
  if link.tooltip.isSome:
    result["tooltip"] = %link.tooltip.get
  if link.data.isSome:
    result["data"] = link.data.get

proc toJson*(params: ExecuteCommandParams): JsonNode =
  ## Serialize ExecuteCommandParams to JSON
  result = %*{"command": params.command}
  if params.arguments.isSome:
    result["arguments"] = %params.arguments.get

# JSON parsing helpers
proc parsePosition*(node: JsonNode): Position =
  ## Defensive against malformed server JSON: a server sending null/non-object
  ## (or omitting a field) where a Position is expected must not crash the
  ## client. The `{}` accessor and `getInt` return safe defaults (0) instead of
  ## raising an (uncatchable) Defect on the worker thread.
  Position(line: node{"line"}.getInt, character: node{"character"}.getInt)

proc parseRange*(node: JsonNode): Range =
  Range(start: parsePosition(node{"start"}), `end`: parsePosition(node{"end"}))

proc parseLocation*(node: JsonNode): Location =
  ## Use `{}` so a missing `uri`/`range` yields an empty URI instead of a
  ## KeyError that would wipe the whole Location list in parseLocations.
  Location(uri: node{"uri"}.getStr, range: parseRange(node{"range"}))

proc parseLocationLink*(node: JsonNode): LocationLink =
  result.targetUri = node{"targetUri"}.getStr
  result.targetRange = parseRange(node{"targetRange"})
  result.targetSelectionRange = parseRange(node{"targetSelectionRange"})
  if node.hasKey("originSelectionRange"):
    result.originSelectionRange = some(parseRange(node{"originSelectionRange"}))

proc locationLinkToLocation*(link: LocationLink): Location =
  ## Convert LocationLink to Location (uses targetSelectionRange for precise navigation)
  Location(uri: link.targetUri, range: link.targetSelectionRange)

proc parseTextEdit*(node: JsonNode): TextEdit =
  TextEdit(range: parseRange(node{"range"}), newText: node{"newText"}.getStr)

proc parseTextDocumentEdit*(node: JsonNode): TextDocumentEdit =
  let tdoc = node{"textDocument"}
  result.textDocument.uri = tdoc{"uri"}.getStr
  let versionNode = tdoc{"version"}
  if versionNode != nil and versionNode.kind != JNull:
    result.textDocument.version = some(versionNode.getInt)
  let editsNode = node{"edits"}
  if editsNode != nil and editsNode.kind == JArray:
    for edit in editsNode:
      if edit.kind == JObject:
        result.edits.add(parseTextEdit(edit))

proc parseWorkspaceEdit*(node: JsonNode): WorkspaceEdit =
  # Both fields are optional and a server may send `null` (e.g. nimlangserver
  # returns `"documentChanges": null` alongside a populated `changes`). Iterating
  # a JNull/JString node raises an AssertionDefect, so guard the kind before
  # iterating. A `null` documentChanges must leave `result.documentChanges`
  # unset (none) rather than `some(@[])`, otherwise applyWorkspaceEdit — which
  # gives documentChanges precedence — would treat it as an empty edit and
  # silently drop the real `changes`.
  let changesNode = node.getOrDefault("changes")
  if changesNode != nil and changesNode.kind == JObject:
    var changes = initTable[string, seq[TextEdit]]()
    for uri, edits in changesNode.pairs:
      if edits.kind != JArray:
        continue
      var editSeq: seq[TextEdit] = @[]
      for edit in edits:
        if edit.kind == JObject:
          editSeq.add(parseTextEdit(edit))
      changes[uri] = editSeq
    result.changes = some(changes)
  let docChangesNode = node.getOrDefault("documentChanges")
  if docChangesNode != nil and docChangesNode.kind == JArray:
    var docChanges: seq[TextDocumentEdit] = @[]
    for docChange in docChangesNode:
      if docChange.kind != JObject:
        continue
      if docChange.hasKey("textDocument"):
        docChanges.add(parseTextDocumentEdit(docChange))
      elif docChange.hasKey("kind"):
        # A CreateFile/RenameFile/DeleteFile resource operation. Record its
        # kind so applyWorkspaceEdit can refuse the whole edit rather than
        # silently dropping the file operation and applying only text edits.
        result.resourceOperations.add(docChange["kind"].getStr)
    # Only treat documentChanges as present when it actually carries something.
    # An empty (or wholly-skipped) array must NOT shadow a populated `changes`
    # map: applyWorkspaceEdit gives documentChanges precedence, so `some(@[])`
    # would silently drop the real edits and still report the apply as success.
    if docChanges.len > 0 or result.resourceOperations.len > 0:
      result.documentChanges = some(docChanges)

# Range-checked enum conversions for server-provided integers.
# A raw `Enum(getInt)` raises RangeDefect on out-of-range values, and a
# Defect on the worker thread is uncatchable and kills the whole process,
# so a misbehaving server must never be able to trigger one.

proc toEnumOr*[T: enum](v: int, default: T): T =
  if v in T.low.ord .. T.high.ord:
    T(v)
  else:
    default

proc toEnum*[T: enum](v: int): Option[T] =
  if v in T.low.ord .. T.high.ord:
    some(T(v))
  else:
    none(T)

# Range-safe jsony parse hooks for LSP integer enums.
#
# jsony's built-in enum parseHook does a raw `T(parseInt(...))` for numeric
# JSON values, which raises RangeDefect when a server sends a value outside the
# enum (e.g. a CompletionItemKind from a newer LSP revision). These overrides
# clamp out-of-range values to the enum default instead, mirroring the defensive
# behaviour of the hand-written toEnum* parsers so a misbehaving server can
# never crash a typed fromJson.
template defLspIntEnum(T: typedesc) =
  proc parseHook*(s: string, i: var int, v: var T) =
    var n: int
    parseHook(s, i, n)
    # Clamp out-of-range values to the lowest valid member rather than
    # default(T): these enums start at 1, so default(T) would yield an invalid
    # ord-0 value with no name.
    v = toEnumOr[T](n, low(T))

  proc dumpHook*(s: var string, v: T) =
    # LSP wants the numeric value on the wire; jsony's default enum dumpHook
    # emits the symbol name ("cikFunction") instead, which servers reject.
    s.add $ord(v)

defLspIntEnum(CompletionItemKind)
defLspIntEnum(InsertTextFormat)
defLspIntEnum(SymbolKind)
defLspIntEnum(DiagnosticSeverity)

proc parseDiagnostic*(node: JsonNode): Diagnostic =
  result.range = parseRange(node["range"])
  result.message = node["message"].getStr

  if node.hasKey("severity"):
    result.severity = toEnum[DiagnosticSeverity](node["severity"].getInt)
  if node.hasKey("code"):
    result.code = some(node["code"])
  if node.hasKey("source"):
    result.source = some(node["source"].getStr)
  if node.hasKey("tags"):
    var tags: seq[DiagnosticTag] = @[]
    for t in node["tags"]:
      let tag = toEnum[DiagnosticTag](t.getInt)
      if tag.isSome:
        tags.add(tag.get)
    result.tags = some(tags)

proc parseCompletionItem*(node: JsonNode): CompletionItem =
  result.label = node["label"].getStr

  if node.hasKey("kind"):
    result.kind = toEnum[CompletionItemKind](node["kind"].getInt)
  if node.hasKey("detail"):
    result.detail = some(node["detail"].getStr)
  if node.hasKey("documentation"):
    result.documentation = some(node["documentation"])
  if node.hasKey("insertText"):
    result.insertText = some(node["insertText"].getStr)
  if node.hasKey("insertTextFormat"):
    result.insertTextFormat = toEnum[InsertTextFormat](node["insertTextFormat"].getInt)
  if node.hasKey("sortText"):
    result.sortText = some(node["sortText"].getStr)
  if node.hasKey("filterText"):
    result.filterText = some(node["filterText"].getStr)
  if node.hasKey("deprecated"):
    result.deprecated = some(node["deprecated"].getBool)
  if node.hasKey("preselect"):
    result.preselect = some(node["preselect"].getBool)
  if node.hasKey("textEdit"):
    result.textEdit = some(node["textEdit"])
  if node.hasKey("additionalTextEdits"):
    var edits: seq[TextEdit] = @[]
    for e in node["additionalTextEdits"]:
      edits.add(parseTextEdit(e))
    result.additionalTextEdits = some(edits)
  if node.hasKey("data"):
    result.data = some(node["data"])

proc parseHover*(node: JsonNode): Hover =
  result.contents = node["contents"]
  if node.hasKey("range"):
    result.range = some(parseRange(node["range"]))

proc parseParameterInformation*(node: JsonNode): ParameterInformation =
  ## Parse parameter information from JSON
  # Label can be string or [start, end] tuple - we handle both
  if node.hasKey("label"):
    if node["label"].kind == JString:
      result.label = node["label"].getStr
    elif node["label"].kind == JArray and node["label"].len == 2:
      let a = node["label"][0].getInt
      let b = node["label"][1].getInt
      result.labelOffsets = some((start: a, stop: b))
  if node.hasKey("documentation"):
    result.documentation = some(node["documentation"])

proc parseSignatureInformation*(node: JsonNode): SignatureInformation =
  ## Parse signature information from JSON
  result.label = node["label"].getStr
  if node.hasKey("documentation"):
    result.documentation = some(node["documentation"])
  if node.hasKey("parameters"):
    var params: seq[ParameterInformation] = @[]
    for p in node["parameters"]:
      params.add(parseParameterInformation(p))
    result.parameters = some(params)
  if node.hasKey("activeParameter"):
    result.activeParameter = some(node["activeParameter"].getInt)

proc parseSignatureHelp*(node: JsonNode): SignatureHelp =
  ## Parse signature help response from JSON
  if node.hasKey("signatures"):
    for sig in node["signatures"]:
      result.signatures.add(parseSignatureInformation(sig))
  if node.hasKey("activeSignature"):
    result.activeSignature = some(node["activeSignature"].getInt)
  if node.hasKey("activeParameter"):
    result.activeParameter = some(node["activeParameter"].getInt)

proc parseDocumentSymbol*(node: JsonNode): DocumentSymbol =
  ## Parse DocumentSymbol from JSON (hierarchical format)
  result.name = node["name"].getStr
  result.kind = toEnumOr[SymbolKind](node["kind"].getInt, skFile)
  result.range = parseRange(node["range"])
  result.selectionRange = parseRange(node["selectionRange"])

  if node.hasKey("detail") and node["detail"].kind != JNull:
    result.detail = some(node["detail"].getStr)
  if node.hasKey("deprecated"):
    result.deprecated = some(node["deprecated"].getBool)
  if node.hasKey("tags") and node["tags"].kind == JArray:
    var tags: seq[int] = @[]
    for t in node["tags"]:
      tags.add(t.getInt)
    result.tags = some(tags)
  if node.hasKey("children") and node["children"].kind == JArray:
    var children: seq[DocumentSymbol] = @[]
    for child in node["children"]:
      children.add(parseDocumentSymbol(child))
    result.children = some(children)

proc parseSymbolInformation*(node: JsonNode): SymbolInformation =
  ## Parse SymbolInformation from JSON (flat format)
  result.name = node["name"].getStr
  result.kind = toEnumOr[SymbolKind](node["kind"].getInt, skFile)
  result.location = parseLocation(node["location"])

  if node.hasKey("deprecated"):
    result.deprecated = some(node["deprecated"].getBool)
  if node.hasKey("tags") and node["tags"].kind == JArray:
    var tags: seq[int] = @[]
    for t in node["tags"]:
      tags.add(t.getInt)
    result.tags = some(tags)
  if node.hasKey("containerName") and node["containerName"].kind != JNull:
    result.containerName = some(node["containerName"].getStr)

proc parseInlayHintLabelPart*(node: JsonNode): InlayHintLabelPart =
  ## Parse InlayHintLabelPart from JSON
  result.value = node["value"].getStr
  if node.hasKey("tooltip"):
    result.tooltip = some(node["tooltip"])
  if node.hasKey("location"):
    result.location = some(parseLocation(node["location"]))
  if node.hasKey("command"):
    result.command = some(node["command"])

proc parseInlayHint*(node: JsonNode): Option[InlayHint] =
  ## Parse InlayHint from JSON. Returns none if node is nil or not an object.
  if node.isNil or node.kind != JObject:
    return none(InlayHint)

  var hint: InlayHint
  if not node.hasKey("position") or not node.hasKey("label"):
    return none(InlayHint)

  # parsePosition indexes node["line"]/["character"] directly, which raises
  # KeyError on a present-but-malformed position. Guard here so a non-conforming
  # server drops the single item (the documented behavior) instead of crashing
  # the render/tick path that calls parseInlayHintResponse.
  let posNode = node["position"]
  if posNode.kind != JObject or not posNode.hasKey("line") or
      not posNode.hasKey("character"):
    return none(InlayHint)

  hint.position = parsePosition(posNode)

  # label is `string | InlayHintLabelPart[]`. getInlayHintLabel indexes each
  # array element as an object (part["value"]), which raises a Defect on a
  # non-object element (e.g. a server returning `"label": ["x"]`). Validate
  # here and drop the single item (the documented behavior) instead of
  # crashing the render/tick path that calls parseInlayHintResponse.
  let labelNode = node["label"]
  case labelNode.kind
  of JString:
    discard
  of JArray:
    for part in labelNode:
      if part.kind != JObject or not part.hasKey("value"):
        return none(InlayHint)
  else:
    return none(InlayHint)
  hint.label = labelNode
  if node.hasKey("kind"):
    hint.kind = toEnum[InlayHintKind](node["kind"].getInt)
  if node.hasKey("textEdits"):
    let textEditsNode = node["textEdits"]
    if textEditsNode.kind == JArray:
      var edits: seq[TextEdit] = @[]
      for edit in textEditsNode:
        if edit.kind == JObject:
          edits.add(parseTextEdit(edit))
      hint.textEdits = some(edits)
  if node.hasKey("tooltip"):
    hint.tooltip = some(node["tooltip"])
  if node.hasKey("paddingLeft"):
    hint.paddingLeft = some(node["paddingLeft"].getBool)
  if node.hasKey("paddingRight"):
    hint.paddingRight = some(node["paddingRight"].getBool)
  if node.hasKey("data"):
    hint.data = some(node["data"])

  return some(hint)

proc getInlayHintLabel*(hint: InlayHint): string =
  ## Extract the label string from an inlay hint
  case hint.label.kind
  of JString:
    return hint.label.getStr
  of JArray:
    # Concatenate all label parts
    for part in hint.label:
      if part.hasKey("value"):
        result.add(part["value"].getStr)
  else:
    return ""

proc parseSelectionRange*(node: JsonNode): SelectionRange =
  ## Parse SelectionRange from JSON (recursive structure)
  ## Returns nil if node is invalid
  if node.isNil or node.kind == JNull or not node.hasKey("range"):
    return nil

  result = SelectionRange()
  result.range = parseRange(node["range"])
  if node.hasKey("parent") and node["parent"].kind != JNull:
    result.parent = parseSelectionRange(node["parent"])

proc parseDocumentHighlight*(node: JsonNode): DocumentHighlight =
  ## Parse DocumentHighlight from JSON
  result.range = parseRange(node["range"])
  if node.hasKey("kind") and node["kind"].kind == JInt:
    result.kind = toEnum[DocumentHighlightKind](node["kind"].getInt)

proc parseDocumentLink*(node: JsonNode): DocumentLink =
  ## Parse DocumentLink from JSON
  result.range = parseRange(node["range"])
  if node.hasKey("target") and node["target"].kind == JString:
    result.target = some(node["target"].getStr)
  if node.hasKey("tooltip") and node["tooltip"].kind == JString:
    result.tooltip = some(node["tooltip"].getStr)
  if node.hasKey("data"):
    result.data = some(node["data"])

proc parseSemanticTokensLegend*(node: JsonNode): SemanticTokensLegend =
  ## Parse SemanticTokensLegend from JSON
  if node.hasKey("tokenTypes"):
    for t in node["tokenTypes"]:
      result.tokenTypes.add(t.getStr)
  if node.hasKey("tokenModifiers"):
    for m in node["tokenModifiers"]:
      result.tokenModifiers.add(m.getStr)

proc parseSemanticTokensOptions*(node: JsonNode): SemanticTokensOptions =
  ## Parse SemanticTokensOptions from JSON
  if node.hasKey("legend"):
    result.legend = parseSemanticTokensLegend(node["legend"])
  if node.hasKey("range"):
    result.range = some(node["range"])
  if node.hasKey("full"):
    result.full = some(node["full"])

proc parseExecuteCommandOptions*(node: JsonNode): ExecuteCommandOptions =
  ## Parse ExecuteCommandOptions from JSON
  if node.hasKey("commands"):
    for cmd in node["commands"]:
      result.commands.add(cmd.getStr)
  if node.hasKey("workDoneProgress"):
    result.workDoneProgress = some(node["workDoneProgress"].getBool)

proc parseWorkDoneProgressBegin*(node: JsonNode): WorkDoneProgressBegin =
  ## Parse WorkDoneProgressBegin from JSON
  result.title = node["title"].getStr
  if node.hasKey("cancellable"):
    result.cancellable = some(node["cancellable"].getBool)
  if node.hasKey("message"):
    result.message = some(node["message"].getStr)
  if node.hasKey("percentage"):
    result.percentage = some(node["percentage"].getInt)

proc parseWorkDoneProgressReport*(node: JsonNode): WorkDoneProgressReport =
  ## Parse WorkDoneProgressReport from JSON
  if node.hasKey("cancellable"):
    result.cancellable = some(node["cancellable"].getBool)
  if node.hasKey("message"):
    result.message = some(node["message"].getStr)
  if node.hasKey("percentage"):
    result.percentage = some(node["percentage"].getInt)

proc parseWorkDoneProgressEnd*(node: JsonNode): WorkDoneProgressEnd =
  ## Parse WorkDoneProgressEnd from JSON
  if node.hasKey("message"):
    result.message = some(node["message"].getStr)

proc parseWorkDoneProgress*(node: JsonNode): WorkDoneProgress =
  ## Parse WorkDoneProgress value from JSON
  let kindStr = node["kind"].getStr
  case kindStr
  of "begin":
    result = WorkDoneProgress(kind: wdpkBegin, begin: parseWorkDoneProgressBegin(node))
  of "report":
    result =
      WorkDoneProgress(kind: wdpkReport, report: parseWorkDoneProgressReport(node))
  of "end":
    result = WorkDoneProgress(kind: wdpkEnd, `end`: parseWorkDoneProgressEnd(node))
  else:
    raise newException(ValueError, "Unknown work done progress kind: " & kindStr)

proc parseWorkDoneProgressParams*(node: JsonNode): WorkDoneProgressParams =
  ## Parse WorkDoneProgressParams ($/progress notification) from JSON
  result.token = node["token"]
  result.value = parseWorkDoneProgress(node["value"])

proc getProgressToken*(params: WorkDoneProgressParams): string =
  ## Get progress token as string (handles both int and string tokens)
  if params.token.kind == JInt:
    $params.token.getInt
  else:
    params.token.getStr

proc parseServerCapabilities*(node: JsonNode): ServerCapabilities =
  # Return empty capabilities if node is not a JObject
  if node.isNil or node.kind != JObject:
    return result
  if node.hasKey("textDocumentSync"):
    result.textDocumentSync = some(node["textDocumentSync"])
  if node.hasKey("completionProvider"):
    let cp = node["completionProvider"]
    # A server may advertise a literal `false` (or `null`, via Option-field
    # serialisation) to disable the feature. The spec types this as Options,
    # but be defensive: only a truthy/object value counts as supported so we
    # never fire requests that hang until the timeout.
    if cp.kind != JNull and (cp.kind != JBool or cp.getBool):
      var opts = CompletionOptions()
      if cp.kind == JObject:
        if cp.hasKey("triggerCharacters"):
          var chars: seq[string] = @[]
          for c in cp["triggerCharacters"]:
            chars.add(c.getStr)
          opts.triggerCharacters = some(chars)
        if cp.hasKey("resolveProvider"):
          opts.resolveProvider = some(cp["resolveProvider"].getBool)
      result.completionProvider = some(opts)
  if node.hasKey("signatureHelpProvider"):
    let sh = node["signatureHelpProvider"]
    # See completionProvider above: skip literal `false` and `null`.
    if sh.kind != JNull and (sh.kind != JBool or sh.getBool):
      var opts = SignatureHelpOptions()
      if sh.kind == JObject:
        if sh.hasKey("triggerCharacters"):
          var chars: seq[string] = @[]
          for c in sh["triggerCharacters"]:
            chars.add(c.getStr)
          opts.triggerCharacters = some(chars)
        if sh.hasKey("retriggerCharacters"):
          var chars: seq[string] = @[]
          for c in sh["retriggerCharacters"]:
            chars.add(c.getStr)
          opts.retriggerCharacters = some(chars)
      result.signatureHelpProvider = some(opts)
  if node.hasKey("hoverProvider"):
    result.hoverProvider = some(node["hoverProvider"])
  if node.hasKey("definitionProvider"):
    result.definitionProvider = some(node["definitionProvider"])
  if node.hasKey("declarationProvider"):
    result.declarationProvider = some(node["declarationProvider"])
  if node.hasKey("typeDefinitionProvider"):
    result.typeDefinitionProvider = some(node["typeDefinitionProvider"])
  if node.hasKey("implementationProvider"):
    result.implementationProvider = some(node["implementationProvider"])
  if node.hasKey("referencesProvider"):
    result.referencesProvider = some(node["referencesProvider"])
  if node.hasKey("documentHighlightProvider"):
    result.documentHighlightProvider = some(node["documentHighlightProvider"])
  if node.hasKey("documentLinkProvider"):
    result.documentLinkProvider = some(node["documentLinkProvider"])
  if node.hasKey("documentSymbolProvider"):
    result.documentSymbolProvider = some(node["documentSymbolProvider"])
  if node.hasKey("codeActionProvider"):
    result.codeActionProvider = some(node["codeActionProvider"])
  if node.hasKey("documentFormattingProvider"):
    result.documentFormattingProvider = some(node["documentFormattingProvider"])
  if node.hasKey("documentRangeFormattingProvider"):
    result.documentRangeFormattingProvider =
      some(node["documentRangeFormattingProvider"])
  if node.hasKey("renameProvider"):
    result.renameProvider = some(node["renameProvider"])
  if node.hasKey("executeCommandProvider"):
    let ec = node["executeCommandProvider"]
    # See completionProvider above: skip literal `false` and `null`.
    if ec.kind != JNull and (ec.kind != JBool or ec.getBool):
      result.executeCommandProvider = some(parseExecuteCommandOptions(ec))
  if node.hasKey("semanticTokensProvider"):
    let stp = node["semanticTokensProvider"]
    # Some servers send a bare `false` / `null` instead of an options object.
    if stp.kind == JObject:
      result.semanticTokensProvider = some(parseSemanticTokensOptions(stp))
  if node.hasKey("inlayHintProvider"):
    result.inlayHintProvider = some(node["inlayHintProvider"])
  if node.hasKey("selectionRangeProvider"):
    result.selectionRangeProvider = some(node["selectionRangeProvider"])
  if node.hasKey("codeLensProvider"):
    result.codeLensProvider = some(node["codeLensProvider"])
  if node.hasKey("callHierarchyProvider"):
    result.callHierarchyProvider = some(node["callHierarchyProvider"])
  if node.hasKey("foldingRangeProvider"):
    result.foldingRangeProvider = some(node["foldingRangeProvider"])

# CodeLens serialization and parsing
proc toJson*(cmd: Command): JsonNode =
  ## Serialize Command to JSON
  result = %*{"title": cmd.title, "command": cmd.command}
  if cmd.arguments.isSome:
    result["arguments"] = %cmd.arguments.get

proc toJson*(lens: CodeLens): JsonNode =
  ## Serialize CodeLens to JSON (for resolve request)
  result = %*{"range": lens.range.toJson}
  if lens.command.isSome:
    result["command"] = lens.command.get.toJson
  if lens.data.isSome:
    result["data"] = lens.data.get

proc toJson*(params: CodeLensParams): JsonNode =
  ## Serialize CodeLensParams to JSON
  %*{"textDocument": params.textDocument.toJson}

proc parseCommand*(node: JsonNode): Command =
  ## Parse Command from JSON
  result.title = node["title"].getStr
  result.command = node["command"].getStr
  if node.hasKey("arguments") and node["arguments"].kind == JArray:
    var args: seq[JsonNode] = @[]
    for arg in node["arguments"]:
      args.add(arg)
    result.arguments = some(args)

proc parseCodeLens*(node: JsonNode): CodeLens =
  ## Parse CodeLens from JSON
  result.range = parseRange(node["range"])
  if node.hasKey("command") and node["command"].kind == JObject:
    result.command = some(parseCommand(node["command"]))
  if node.hasKey("data"):
    result.data = some(node["data"])

# Code Action serialization and parsing
proc toJson*(context: CodeActionContext): JsonNode =
  ## Serialize CodeActionContext to JSON
  result = newJObject()
  var diagArray = newJArray()
  for diag in context.diagnostics:
    var diagNode = %*{"range": diag.range.toJson, "message": diag.message}
    if diag.severity.isSome:
      diagNode["severity"] = %diag.severity.get.int
    if diag.code.isSome:
      diagNode["code"] = diag.code.get
    if diag.source.isSome:
      diagNode["source"] = %diag.source.get
    diagArray.add(diagNode)
  result["diagnostics"] = diagArray
  if context.only.isSome:
    result["only"] = %context.only.get
  if context.triggerKind.isSome:
    result["triggerKind"] = %context.triggerKind.get

proc toJson*(params: CodeActionParams): JsonNode =
  ## Serialize CodeActionParams to JSON
  %*{
    "textDocument": params.textDocument.toJson,
    "range": params.range.toJson,
    "context": params.context.toJson,
  }

proc parseCodeAction*(node: JsonNode): CodeAction =
  ## Parse CodeAction from JSON
  result.title = node["title"].getStr
  if node.hasKey("kind") and node["kind"].kind == JString:
    result.kind = some(node["kind"].getStr)
  if node.hasKey("diagnostics") and node["diagnostics"].kind == JArray:
    var diags: seq[Diagnostic] = @[]
    for d in node["diagnostics"]:
      diags.add(parseDiagnostic(d))
    result.diagnostics = some(diags)
  if node.hasKey("isPreferred"):
    result.isPreferred = some(node["isPreferred"].getBool)
  if node.hasKey("disabled"):
    result.disabled = some(node["disabled"])
  if node.hasKey("edit") and node["edit"].kind == JObject:
    result.edit = some(parseWorkspaceEdit(node["edit"]))
  if node.hasKey("command") and node["command"].kind == JObject:
    result.command = some(parseCommand(node["command"]))
  if node.hasKey("data"):
    result.data = some(node["data"])

proc toJson*(action: CodeAction): JsonNode =
  ## Serialize CodeAction to JSON (for codeAction/resolve request)
  result = %*{"title": action.title}
  if action.kind.isSome:
    result["kind"] = %action.kind.get
  if action.isPreferred.isSome:
    result["isPreferred"] = %action.isPreferred.get
  if action.disabled.isSome:
    result["disabled"] = action.disabled.get
  if action.data.isSome:
    result["data"] = action.data.get

# Call Hierarchy serialization and parsing
proc parseCallHierarchyItem*(node: JsonNode): CallHierarchyItem =
  ## Parse CallHierarchyItem from JSON
  result.name = node["name"].getStr
  result.kind = toEnumOr[SymbolKind](node["kind"].getInt, skFile)
  result.uri = node["uri"].getStr
  result.range = parseRange(node["range"])
  result.selectionRange = parseRange(node["selectionRange"])
  if node.hasKey("tags") and node["tags"].kind == JArray:
    var tags: seq[int] = @[]
    for t in node["tags"]:
      tags.add(t.getInt)
    result.tags = some(tags)
  if node.hasKey("detail") and node["detail"].kind == JString:
    result.detail = some(node["detail"].getStr)
  if node.hasKey("data"):
    result.data = some(node["data"])

proc toJson*(item: CallHierarchyItem): JsonNode =
  ## Serialize CallHierarchyItem to JSON
  result = %*{
    "name": item.name,
    "kind": item.kind.int,
    "uri": item.uri,
    "range": item.range.toJson,
    "selectionRange": item.selectionRange.toJson,
  }
  if item.tags.isSome:
    result["tags"] = %item.tags.get
  if item.detail.isSome:
    result["detail"] = %item.detail.get
  if item.data.isSome:
    result["data"] = item.data.get

proc parseCallHierarchyIncomingCall*(node: JsonNode): CallHierarchyIncomingCall =
  ## Parse CallHierarchyIncomingCall from JSON
  result.`from` = parseCallHierarchyItem(node["from"])
  for r in node["fromRanges"]:
    result.fromRanges.add(parseRange(r))

proc parseCallHierarchyOutgoingCall*(node: JsonNode): CallHierarchyOutgoingCall =
  ## Parse CallHierarchyOutgoingCall from JSON
  result.to = parseCallHierarchyItem(node["to"])
  for r in node["fromRanges"]:
    result.fromRanges.add(parseRange(r))

# Folding Range parsing
proc parseFoldingRangeKind*(s: string): Option[FoldingRangeKind] =
  ## Parse FoldingRangeKind from string
  case s
  of "comment":
    some(frkComment)
  of "imports":
    some(frkImports)
  of "region":
    some(frkRegion)
  else:
    none(FoldingRangeKind)

proc parseFoldingRange*(node: JsonNode): FoldingRange =
  ## Parse FoldingRange from JSON
  result.startLine = node["startLine"].getInt
  result.endLine = node["endLine"].getInt
  if node.hasKey("startCharacter") and node["startCharacter"].kind == JInt:
    result.startCharacter = some(node["startCharacter"].getInt)
  if node.hasKey("endCharacter") and node["endCharacter"].kind == JInt:
    result.endCharacter = some(node["endCharacter"].getInt)
  if node.hasKey("kind") and node["kind"].kind == JString:
    result.kind = parseFoldingRangeKind(node["kind"].getStr)
  if node.hasKey("collapsedText") and node["collapsedText"].kind == JString:
    result.collapsedText = some(node["collapsedText"].getStr)

# Additional helper functions for LSP client

proc parseLocations*(node: JsonNode): seq[Location] =
  ## Parse Location or Location[] from JSON. Malformed entries (non-object or
  ## missing uri) are skipped so one bad item doesn't drop the whole list.
  case node.kind
  of JArray:
    for item in node:
      if item.kind != JObject:
        continue
      let loc = parseLocation(item)
      if loc.uri.len == 0:
        continue
      result.add(loc)
  of JObject:
    let loc = parseLocation(node)
    if loc.uri.len > 0:
      result.add(loc)
  else:
    discard

proc parseDocumentSymbolResult*(node: JsonNode): DocumentSymbolResult =
  ## Parse DocumentSymbol[] or SymbolInformation[] from JSON
  if node.kind != JArray or node.len == 0:
    return DocumentSymbolResult(isHierarchical: true, symbols: @[])

  # Check if first item has "children" or "location" to determine type
  let firstItem = node[0]
  if firstItem.hasKey("location"):
    # SymbolInformation[]
    var syms: seq[SymbolInformation] = @[]
    for item in node:
      syms.add(parseSymbolInformation(item))
    return DocumentSymbolResult(isHierarchical: false, symbolInfos: syms)
  else:
    # DocumentSymbol[]
    var syms: seq[DocumentSymbol] = @[]
    for item in node:
      syms.add(parseDocumentSymbol(item))
    return DocumentSymbolResult(isHierarchical: true, symbols: syms)

proc documentLinkToJson*(link: DocumentLink): JsonNode =
  ## Convert DocumentLink to JSON for documentLink/resolve request
  result = %*{
    "range": {
      "start": {"line": link.range.start.line, "character": link.range.start.character},
      "end": {"line": link.range.`end`.line, "character": link.range.`end`.character},
    }
  }
  if link.target.isSome:
    result["target"] = %link.target.get
  if link.tooltip.isSome:
    result["tooltip"] = %link.tooltip.get
  if link.data.isSome:
    result["data"] = link.data.get

proc codeLensToJson*(lens: CodeLens): JsonNode =
  ## Convert CodeLens to JSON for codeLens/resolve request
  result = newJObject()
  var rangeNode = newJObject()
  rangeNode["start"] =
    %*{"line": lens.range.start.line, "character": lens.range.start.character}
  rangeNode["end"] =
    %*{"line": lens.range.`end`.line, "character": lens.range.`end`.character}
  result["range"] = rangeNode

  if lens.command.isSome:
    let cmd = lens.command.get
    var cmdNode = newJObject()
    cmdNode["title"] = %cmd.title
    cmdNode["command"] = %cmd.command
    if cmd.arguments.isSome:
      var argsArray = newJArray()
      for arg in cmd.arguments.get:
        argsArray.add(arg)
      cmdNode["arguments"] = argsArray
    result["command"] = cmdNode
  if lens.data.isSome:
    result["data"] = lens.data.get

# Dynamic Registration types (LSP 3.17)
type
  Registration* = object ## General parameters to register a capability.
    id*: string ## The id used to register the request. Used to unregister.
    `method`*: string ## The method / capability to register for.
    registerOptions*: Option[JsonNode] ## Options necessary for the registration.

  RegistrationParams* = object ## Parameters for client/registerCapability request.
    registrations*: seq[Registration]

  Unregistration* = object ## General parameters to unregister a capability.
    id*: string ## The id used to unregister the request.
    `method`*: string ## The method / capability to unregister.

  UnregistrationParams* = object ## Parameters for client/unregisterCapability request.
    unregisterations*: seq[Unregistration]
      # Note: LSP spec uses "unregisterations" (typo in spec)

  TextDocumentRegistrationOptions* = object
    ## Options for text document registration (used in dynamic registration)
    documentSelector*: Option[JsonNode]
      # DocumentSelector | null - which documents this applies to

  TextDocumentChangeRegistrationOptions* = object
    ## Options for textDocument/didChange dynamic registration
    documentSelector*: Option[JsonNode]
    syncKind*: Option[TextDocumentSyncKind]

  CompletionRegistrationOptions* = object
    ## Options for textDocument/completion dynamic registration
    documentSelector*: Option[JsonNode]
    triggerCharacters*: Option[seq[string]]
    allCommitCharacters*: Option[seq[string]]
    resolveProvider*: Option[bool]
    workDoneProgress*: Option[bool]

proc parseRegistration*(node: JsonNode): Registration =
  ## Parse Registration from JSON
  result.id = node["id"].getStr
  result.`method` = node["method"].getStr
  if node.hasKey("registerOptions"):
    result.registerOptions = some(node["registerOptions"])

proc parseRegistrationParams*(node: JsonNode): RegistrationParams =
  ## Parse RegistrationParams from JSON
  if node.hasKey("registrations"):
    for reg in node["registrations"]:
      result.registrations.add(parseRegistration(reg))

proc parseUnregistration*(node: JsonNode): Unregistration =
  ## Parse Unregistration from JSON
  result.id = node["id"].getStr
  result.`method` = node["method"].getStr

proc parseUnregistrationParams*(node: JsonNode): UnregistrationParams =
  ## Parse UnregistrationParams from JSON
  # Note: The LSP spec uses "unregisterations" (with typo)
  if node.hasKey("unregisterations"):
    for unreg in node["unregisterations"]:
      result.unregisterations.add(parseUnregistration(unreg))
