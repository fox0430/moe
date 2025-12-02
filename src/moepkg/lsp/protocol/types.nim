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

## LSP Protocol Types
## Based on LSP Specification 3.17

import std/[options, json]

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
    executeCommandProvider*: Option[JsonNode]
    selectionRangeProvider*: Option[JsonNode]
    linkedEditingRangeProvider*: Option[JsonNode]
    callHierarchyProvider*: Option[JsonNode]
    semanticTokensProvider*: Option[JsonNode]
    monikerProvider*: Option[JsonNode]
    typeHierarchyProvider*: Option[JsonNode]
    inlineValueProvider*: Option[JsonNode]
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

# JSON parsing helpers
proc parsePosition*(node: JsonNode): Position =
  Position(line: node["line"].getInt, character: node["character"].getInt)

proc parseRange*(node: JsonNode): Range =
  Range(start: parsePosition(node["start"]), `end`: parsePosition(node["end"]))

proc parseLocation*(node: JsonNode): Location =
  Location(uri: node["uri"].getStr, range: parseRange(node["range"]))

proc parseDiagnostic*(node: JsonNode): Diagnostic =
  result.range = parseRange(node["range"])
  result.message = node["message"].getStr

  if node.hasKey("severity"):
    result.severity = some(DiagnosticSeverity(node["severity"].getInt))
  if node.hasKey("code"):
    result.code = some(node["code"])
  if node.hasKey("source"):
    result.source = some(node["source"].getStr)
  if node.hasKey("tags"):
    var tags: seq[DiagnosticTag] = @[]
    for t in node["tags"]:
      tags.add(DiagnosticTag(t.getInt))
    result.tags = some(tags)

proc parseCompletionItem*(node: JsonNode): CompletionItem =
  result.label = node["label"].getStr

  if node.hasKey("kind"):
    result.kind = some(CompletionItemKind(node["kind"].getInt))
  if node.hasKey("detail"):
    result.detail = some(node["detail"].getStr)
  if node.hasKey("documentation"):
    result.documentation = some(node["documentation"])
  if node.hasKey("insertText"):
    result.insertText = some(node["insertText"].getStr)
  if node.hasKey("insertTextFormat"):
    result.insertTextFormat = some(InsertTextFormat(node["insertTextFormat"].getInt))
  if node.hasKey("sortText"):
    result.sortText = some(node["sortText"].getStr)
  if node.hasKey("filterText"):
    result.filterText = some(node["filterText"].getStr)
  if node.hasKey("deprecated"):
    result.deprecated = some(node["deprecated"].getBool)
  if node.hasKey("preselect"):
    result.preselect = some(node["preselect"].getBool)

proc parseHover*(node: JsonNode): Hover =
  result.contents = node["contents"]
  if node.hasKey("range"):
    result.range = some(parseRange(node["range"]))

proc parseServerCapabilities*(node: JsonNode): ServerCapabilities =
  if node.hasKey("textDocumentSync"):
    result.textDocumentSync = some(node["textDocumentSync"])
  if node.hasKey("completionProvider"):
    let cp = node["completionProvider"]
    var opts = CompletionOptions()
    if cp.hasKey("triggerCharacters"):
      var chars: seq[string] = @[]
      for c in cp["triggerCharacters"]:
        chars.add(c.getStr)
      opts.triggerCharacters = some(chars)
    if cp.hasKey("resolveProvider"):
      opts.resolveProvider = some(cp["resolveProvider"].getBool)
    result.completionProvider = some(opts)
  if node.hasKey("hoverProvider"):
    result.hoverProvider = some(node["hoverProvider"])
  if node.hasKey("definitionProvider"):
    result.definitionProvider = some(node["definitionProvider"])
  if node.hasKey("declarationProvider"):
    result.declarationProvider = some(node["declarationProvider"])
  if node.hasKey("referencesProvider"):
    result.referencesProvider = some(node["referencesProvider"])
  if node.hasKey("documentSymbolProvider"):
    result.documentSymbolProvider = some(node["documentSymbolProvider"])
  if node.hasKey("documentFormattingProvider"):
    result.documentFormattingProvider = some(node["documentFormattingProvider"])
  if node.hasKey("renameProvider"):
    result.renameProvider = some(node["renameProvider"])
  if node.hasKey("semanticTokensProvider"):
    result.semanticTokensProvider = some(node["semanticTokensProvider"])
  if node.hasKey("inlayHintProvider"):
    result.inlayHintProvider = some(node["inlayHintProvider"])
