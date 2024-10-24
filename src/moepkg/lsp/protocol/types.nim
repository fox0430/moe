## Copyright (c) 2023 The core Nim team
## https://github.com/nim-lang/langserver

# NOTE: Language Server Protocol Specification - 3.17
# https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/

import std/[json, options]
import enums

type
  OptionalSeq*[T] = Option[seq[T]]
  OptionalNode = Option[JsonNode]

  CancelParams* = ref object of RootObj
    id*: OptionalNode # int | string

  Position* = ref object of RootObj
    line*: int
    character*: int

  Range* = ref object of RootObj
    start*: Position
    `end`*: Position

  Location* = ref object of RootObj
    uri*: string
    `range`*: Range

  Diagnostic* = ref object of RootObj
    `range`*: Range
    severity*: Option[int]
    code*: OptionalNode # int or string
    source*: Option[string]
    message*: string
    relatedInformation*: OptionalSeq[DiagnosticRelatedInformation]

  DiagnosticRelatedInformation* = ref object of RootObj
    location*: Location
    message*: string

  Command* = ref object of RootObj
    title*: string
    command*: string
    arguments*: OptionalNode

  CodeAction* = ref object of RootObj
    command*: Command
    title*: string
    kind*: string

  TextEdit* = ref object of RootObj
    `range`*: Range
    newText*: string

  TextDocumentEdit* = ref object of RootObj
    textDocument*: VersionedTextDocumentIdentifier
    edits*: OptionalSeq[TextEdit]

  WorkspaceEdit* = ref object of RootObj
    changes*: OptionalNode
    documentChanges*: OptionalSeq[TextDocumentEdit]

  DocumentFilter* = ref object of RootObj
    language*: Option[string]
    scheme*: Option[string]
    pattern*: Option[string]

  DocumentSelector* = DocumentFilter

  TextDocumentIdentifier* = ref object of RootObj
    uri*: string

  TextDocumentItem* = ref object of RootObj
    uri*: string
    languageId*: string
    version*: int
    text*: string

  TextDocumentPositionParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    position*: Position

  TextDocumentRegistrationOptions* = ref object of RootObj
    documentSelector*: Option[DocumentSelector]

  VersionedTextDocumentIdentifier* = ref object of TextDocumentIdentifier
    version*: OptionalNode # int or float

  ExpandTextDocumentPositionParams* = ref object of TextDocumentPositionParams
    level*: Option[int]

  MarkupContent* = ref object of RootObj
    kind*: string
    value*: string

  ClientInfo* = ref object of RootObj
    name*: string
    version*: Option[string]

  InitializeParams* = ref object of RootObj
    processId*: OptionalNode # int or float
    clientInfo*: Option[ClientInfo]
    locale*: Option[string]
    rootPath*: Option[string]
    rootUri*: Option[string]
    initializationOptions*: OptionalNode
    capabilities*: ClientCapabilities
    trace*: Option[string]
    workspaceFolders*: OptionalSeq[WorkspaceFolder]

  WorkDoneProgressOptions* = ref object of RootObj
    workDoneProgress*: Option[bool]

  WorkDoneProgressBegin* = ref object of RootObj
    kind*: string
    title*: string
    cancellable*: Option[bool]
    message*: Option[string]
    percentage*: Option[int]

  WorkDoneProgressReport* = ref object of RootObj
    kind*: string
    cancellable*: Option[bool]
    message*: Option[string]
    percentage*: Option[int]

  WorkDoneProgressEnd* = ref object of RootObj
    kind*: string
    message*: Option[string]

  WorkDoneProgressCreateParams* = ref object of RootObj
    token*: OptionalNode # int or string (ProgressToken)

  ProgressTokenParams* = ref object of RootObj
    token*: OptionalNode # int or string (ProgressToken)
    value*: OptionalNode # T

  WorkDoneProgressParams* = ref object of RootObj
    workDoneToken*: OptionalNode # ProgressToken

  ConfigurationItem* = ref object of RootObj
    scopeUri*: Option[string]
    section*: Option[string]

  ConfigurationParams* = ref object of RootObj
    items*: seq[ConfigurationItem]

  WorkspaceEditCapability* = ref object of RootObj
    documentChanges*: Option[bool]

  DidChangeConfigurationCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DidChangeWatchedFilesCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  SymbolKindCapability* = ref object of RootObj
    valueSet*: OptionalSeq[int]

  SymbolCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    symbolKind*: Option[SymbolKindCapability]

  ExecuteCommandClientCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  SemanticTokensWorkspaceClientCapabilities* = ref object of RootObj
    refreshSupport*: Option[bool]

  InlayHintWorkspaceClientCapabilities* = ref object of RootObj
    refreshSupport*: Option[bool]

  InlineValueWorkspaceClientCapabilities* = ref object of RootObj
    refreshSupport*: Option[bool]

  WorkspaceClientCapabilities* = ref object of RootObj
    applyEdit*: Option[bool]
    workspaceEdit*: Option[WorkspaceEditCapability]
    didChangeConfiguration*: Option[DidChangeConfigurationCapability]
    didChangeWatchedFiles*: Option[DidChangeWatchedFilesCapability]
    symbol*: Option[SymbolCapability]
    executeCommand*: Option[ExecuteCommandClientCapability]
    workspaceFolders*: Option[bool]
    configuration*: Option[bool]
    codeLens*: Option[CodeLensWorkspaceClientCapabilities]
    semanticTokens*: Option[SemanticTokensWorkspaceClientCapabilities]
    inlayHint*: Option[InlayHintWorkspaceClientCapabilities]
    innlineValue*: Option[InlineValueWorkspaceClientCapabilities]

  TextDocumentSyncClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    willSave*: Option[bool]
    willSaveWaitUntil*: Option[bool]
    didSave*: Option[bool]

  CompletionItemCapability* = ref object of RootObj
    snippetSupport*: Option[bool]
    commitCharactersSupport*: Option[bool]
    documentFormat*: OptionalSeq[string]
    deprecatedSupport*: Option[bool]

  CompletionItemKindCapability* = ref object of RootObj
    valueSet*: OptionalSeq[int]

  CompletionClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    completionItem*: Option[CompletionItemCapability]
    completionItemKind*: Option[CompletionItemKindCapability]
    contextSupport*: Option[bool]

  HoverClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    contentFormat*: OptionalSeq[string]

  ParameterInformationCapability* = ref object of RootObj
    labelOffsetSupport*: Option[bool]

  SignatureInformationCapability* = ref object of RootObj
    documentationFormat*: OptionalSeq[string]
    parameterInformation*: ParameterInformationCapability
    activeParameterSupport*: Option[bool]
    contextSupport*: Option[bool]

  SignatureHelpClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    signatureInformation*: Option[SignatureInformationCapability]

  ReferenceClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DocumentHighlightClientCapabilies* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  TagSupportCapability* = ref object of RootObj
    valueSet*: seq[SymbolTag]

  DocumentSymbolClientCapabilies* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    symbolKind*: Option[SymbolKindCapability]
    hierarchicalDocumentSymbolSupport*: Option[bool]
    tagSupport*: Option[TagSupportCapability]
    labelSupport*: Option[bool]

  DocumentFormattingClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DocumentRangeFormattingClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DocumentOnTypeFormattingClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DefinitionClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  TypeDefinitionClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    linkSupport*:  Option[bool]

  ImplementationClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    linkSupport*: Option[bool]

  CodeActionClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  CodeLensClientClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DocumentLinkCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DocumentColorClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  RenameClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    prepareSupport*: Option[bool]

  PublishDiagnosticsClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  FoldingRangeKindValueSet* = ref object of RootObj
    valueSet*: seq[FoldingRangeKind]

  FoldingRangeFoldingRange* = ref object of RootObj
    collapsedText*: seq[bool]

  FoldingRangeClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    rangeLimit*: Option[uint]
    lineFoldingOnly*: Option[bool]
    foldingRangeKind*: Option[FoldingRangeKindValueSet]
    foldingRange*: Option[FoldingRangeFoldingRange]

  SelectionRangeClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  SemanticTokensClientCapabilitiesRequest* = ref object of RootObj
    range*: Option[bool]
    full*: Option[bool]

  SemanticTokensClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    tokenTypes*: seq[string]
    tokenModifiers*: seq[string]
    formats*: seq[string]
    requests*: SemanticTokensClientCapabilitiesRequest
    overlappingTokenSupport*: Option[bool]
    multilineTokenSupport*: Option[bool]
    serverCancelSupport*: Option[bool]
    augmentsSyntaxTokens*: Option[bool]

  InlayHintClientCapabilitiesResolveSupport* = ref object of RootObj
    properties*: seq[string]

  InlayHintClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    resolveSupport*: Option[InlayHintClientCapabilitiesResolveSupport]

  InlineValueClientCapabilitie* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DeclarationClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    linkSupport*: Option[bool]

  CallHierarchyClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DocumentLinkClientCapabilities* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    toolsopSupport*: Option[bool]

  TextDocumentClientCapabilities* = ref object of RootObj
    synchronization*: Option[TextDocumentSyncClientCapabilities]
    completion*: Option[CompletionClientCapabilities]
    hover*: Option[HoverClientCapabilities]
    signatureHelp*: Option[SignatureHelpClientCapabilities]
    declaration*: Option[DeclarationClientCapabilities]
    definition*: Option[DefinitionClientCapabilities]
    typeDefinition*: Option[TypeDefinitionClientCapabilities]
    implementation*: Option[ImplementationClientCapabilities]
    references*: Option[ReferenceClientCapabilities]
    documentHighlight*: Option[DocumentHighlightClientCapabilies]
    documentSymbol*: Option[DocumentSymbolClientCapabilies]
    codeAction*: Option[CodeActionClientCapabilities]
    codeLens*: Option[CodeLensClientClientCapabilities]
    documentLink*: Option[DocumentLinkClientCapabilities]
    colorProvider*: Option[DocumentColorClientCapabilities]
    formatting*: Option[DocumentFormattingClientCapabilities]
    rangeFormatting*: Option[DocumentRangeFormattingClientCapabilities]
    onTypeFormatting*: Option[DocumentOnTypeFormattingClientCapabilities]
    rename*: Option[RenameClientCapabilities]
    publishDiagnostics*: Option[PublishDiagnosticsClientCapabilities]
    foldingRange*: Option[FoldingRangeClientCapabilities]
    selectionRange*: Option[SelectionRangeClientCapabilities]
    callHierarchy*: Option[CallHierarchyClientCapabilities]
    semanticTokens*: Option[SemanticTokensClientCapabilities]
    inlayHint*: Option[InlayHintClientCapabilities]
    inlineValue*: Option[InlineValueClientCapabilitie]

  WindowCapabilities* = ref object of RootObj
    workDoneProgress*: Option[bool]
    showMessage*: Option[ShowMessageRequestParams]
    showDocument*: Option[ShowDocumentClientCapabilities]

  ClientCapabilities* = ref object of RootObj
    workspace*: Option[WorkspaceClientCapabilities]
    textDocument*: Option[TextDocumentClientCapabilities]
    window*: Option[WindowCapabilities]
    experimental*: OptionalNode

  WorkspaceFolder* = ref object of RootObj
    uri*: string
    name*: string

  InitializeResult* = ref object of RootObj
    capabilities*: ServerCapabilities

  InitializeError* = ref object of RootObj
    retry*: bool

  CompletionOptions* = ref object of RootObj
    resolveProvider*: Option[bool]
    triggerCharacters*: OptionalSeq[string]

  HoverOptions* = ref object of WorkDoneProgressOptions

  SignatureHelpOptions* = ref object of WorkDoneProgressParams
    triggerCharacters*: OptionalSeq[string]
    retriggerCharacters*: OptionalSeq[string]

  DefinitionOptions* = ref object of WorkDoneProgressOptions

  TypeDefinitionOptions* = ref object of WorkDoneProgressOptions

  TypeDefinitionRegistrationOptions * = ref object of TextDocumentRegistrationOptions
    identifier*: Option[string]
    interFileDependencies*: bool
    workspaceDiagnostics*: bool
    partialResultToken*: OptionalNode # ProgressToken

  CodeLensOptions* = ref object of WorkDoneProgressOptions
    resolveProvider*: Option[bool]

  DocumentOnTypeFormattingOptions* = ref object of RootObj
    firstTriggerCharacter*: string
    moreTriggerCharacter*: OptionalSeq[string]

  DocumentLinkOptions* = ref object of RootObj
    resolveProvider*: Option[bool]

  ExecuteCommandOptions* = ref object of WorkDoneProgressOptions
   commands*: seq[string]

  SaveOptions* = ref object of RootObj
    includeText*: Option[bool]

  ColorProviderOptions* = ref object of RootObj

  TextDocumentSyncOptions* = ref object of RootObj
    openClose*: Option[bool]
    change*: Option[TextDocumentSyncKind]

  StaticRegistrationOptions* = ref object of RootObj
    id*: Option[string]

  WorkspaceFolderCapability* = ref object of RootObj
    supported*: Option[bool]
    changeNotifications*: OptionalNode # string or bool

  WorkspaceCapability* = ref object of RootObj
    workspaceFolders*: Option[WorkspaceFolderCapability]

  TextDocumentAndStaticRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    id*: Option[string]
  ReferenceOptions* = ref object of WorkDoneProgressOptions

  RenameOptions* = ref object of RootObj
    prepareProvider*: bool

  SemanticTokensLegend* = ref object of RootObj
    tokenTypes*: seq[string]
    tokenModifiers*: seq[string]

  SemanticTokensOptions* = ref object of WorkDoneProgressOptions
    legend*: SemanticTokensLegend
    range*: OptionalNode # bool or JsonNode
    full*: OptionalNode # bool or JsonNode

  SemanticTokensRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    id*: Option[string]
    legend*: SemanticTokensLegend
    range*: OptionalNode # bool or JsonNode
    full*: OptionalNode # bool or JsonNode

  InlayHintOptions* = ref object of RootObj
    resolveProvider*: Option[bool]

  InlineValueOptions* = ref object of WorkDoneProgressOptions

  InlineValueRegistrationOptions* = ref object of InlineValueOptions
    documentSelector*: Option[DocumentSelector]
    id*: Option[string]

  DiagnosticOptions* = ref object of WorkDoneProgressOptions
    identifier*: Option[string]
    interFileDependencies*: bool
    workspaceDiagnostics*: bool

  DiagnosticRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    identifier*: Option[string]
    interFileDependencies*: bool
    workspaceDiagnostics*: bool
    id*: Option[string]

  FoldingRangeOptions* = ref object of WorkDoneProgressOptions

  SelectionRangeOptions* = ref object of WorkDoneProgressOptions

  SelectionRangeRegistrationOptions* = ref object of WorkDoneProgressParams
    workDoneProgress*: Option[bool]
    documentSelector*: Option[DocumentSelector]
    id*: Option[string]

  ImplementationOptions* = ref object of WorkDoneProgressOptions

  DeclarationOptions* = ref object of WorkDoneProgressOptions

  DeclarationRegistrationOptions* = ref object of TextDocumentPositionParams
    workDoneToken*: OptionalNode # ProgressToken
    partialResultToken*: OptionalNode # ProgressToken

  CallHierarchyOptions* = ref object of WorkDoneProgressOptions

  CallHierarchyRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    workDoneProgress*: Option[bool]
    id*: Option[string]

  DocumentHighlightOptions* = ref object of TextDocumentRegistrationOptions
    workDoneProgress*: Option[bool]

  DocumentSymbolOptions* = ref object of WorkDoneProgressOptions
    label*: Option[string]

  CodeActionOptions* = ref object of WorkDoneProgressOptions
    codeActionKinds*: seq[string]
    resolveProvider*: Option[bool]

  DocumentFormattingOptions* = ref object of WorkDoneProgressOptions

  DocumentRangeFormattingOptions* = ref object of WorkDoneProgressOptions

  WorkspaceSymbolOptions* = ref object of WorkDoneProgressOptions
    resolveProvider*: Option[bool]

  ServerCapabilities* = ref object of RootObj
    textDocumentSync*: OptionalNode # TextDocumentSyncOptions or int
    hoverProvider*: OptionalNode # bool | HoverOptions
    completionProvider*: Option[CompletionOptions]
    signatureHelpProvider*: Option[SignatureHelpOptions]
    declarationProvider*: OptionalNode # bool | DeclarationOptions | DeclarationRegistrationOptions
    definitionProvider*: OptionalNode # bool | DefinitionOptions
    typeDefinitionProvider*: OptionalNode # bool | TypeDefinitionOptions | TypeDefinitionRegistrationOptions
    implementationProvider*: OptionalNode # bool | ImplementationOptions | TextDocumentAndStaticRegistrationOptions
    referencesProvider*: OptionalNode # bool | ReferenceOptions
    documentHighlightProvider*: OptionalNode # bool | DocumentHighlightOptions
    documentSymbolProvider*: OptionalNode # bool | DocumentSymbolOptions
    workspaceSymbolProvider*: OptionalNode # bool | WorkspaceSymbolOptions
    codeActionProvider*: OptionalNode # bool | CodeActionOptions
    codeLensProvider*: Option[CodeLensOptions]
    documentFormattingProvider*: OptionalNode # bool | DocumentFormattingOptions
    documentRangeFormattingProvider*: OptionalNode # bool | DocumentRangeFormattingOptions
    documentOnTypeFormattingProvider*: Option[DocumentOnTypeFormattingOptions]
    renameProvider*: OptionalNode # bool or RenameOptions
    documentLinkProvider*: Option[DocumentLinkOptions]
    colorProvider*: OptionalNode # bool | ColorProviderOptions | TextDocumentAndStaticRegistrationOptions
    workspace*: Option[WorkspaceCapability]
    semanticTokensProvider*: OptionalNode # SemanticTokensOptions | SemanticTokensRegistrationOptions
    inlayHintProvider*: OptionalNode # bool | InlayHintOptions | InlayHintRegistrationOptions
    inlineValueProvider*: OptionalNode # bool InlineValueOptions | InlineValueRegistrationOptions
    diagnosticProvider*: OptionalNode # DiagnosticOptions | DiagnosticRegistrationOptions
    foldingRangeProvider*: OptionalNode # bool | FoldingRangeOptions
    selectionRangeProvider*: OptionalNode # bool | SelectionRangeOptions | SelectionRangeRegistrationOptions
    callHierarchyProvider*: OptionalNode # bool | CallHierarchyOptions | CallHierarchyRegistrationOptions
    executeCommandProvider*: Option[ExecuteCommandOptions]
    experimental*: OptionalNode

  InitializedParams* = ref object of RootObj
    DUMMY*: Option[nil]

  ShowMessageParams* = ref object of RootObj
    `type`*: int
    message*: string

  MessageActionItem* = ref object of RootObj
    title*: string

  ShowMessageRequestParams* = ref object of RootObj
    `type`*: int
    message*: string
    actions*: OptionalSeq[MessageActionItem]

  ShowDocumentClientCapabilities* = ref object of RootObj
    support*: bool

  LogMessageParams* = ref object of RootObj
    `type`*: int
    message*: string

  Registration* = ref object of RootObj
    id*: string
    `method`*: string
    registrationOptions*: OptionalNode

  RegistrationParams* = ref object of RootObj
    registrations*: OptionalSeq[Registration]

  Unregistration* = ref object of RootObj
    id*: string
    `method`*: string

  UnregistrationParams* = ref object of RootObj
    unregistrations*: OptionalSeq[Unregistration]

  WorkspaceFoldersChangeEvent* = ref object of RootObj
    added*: OptionalSeq[WorkspaceFolder]
    removed*: OptionalSeq[WorkspaceFolder]

  DidChangeWorkspaceFoldersParams* = ref object of RootObj
    event*: WorkspaceFoldersChangeEvent

  DidChangeConfigurationParams* = ref object of RootObj
    settings*: OptionalNode

  FileEvent* = ref object of RootObj
    uri*: string
    `type`*: int

  DidChangeWatchedFilesParams* = ref object of RootObj
    changes*: OptionalSeq[FileEvent]

  DidChangeWatchedFilesRegistrationOptions* = ref object of RootObj
    watchers*: OptionalSeq[FileSystemWatcher]

  FileSystemWatcher* = ref object of RootObj
    globPattern*: string
    kind*: Option[int]

  WorkspaceSymbolParams* = ref object of RootObj
    query*: string

  ExecuteCommandParams* = ref object of WorkDoneProgressParams
    command*: string
    arguments*: JsonNode # LSPAny[]

  ExecuteCommandRegistrationOptions* = ref object of RootObj
    commands*: OptionalSeq[string]

  ApplyWorkspaceEditParams* = ref object of RootObj
    label*: Option[string]
    edit*: WorkspaceEdit

  ApplyWorkspaceEditResponse* = ref object of RootObj
    applied*: bool

  DidOpenTextDocumentParams* = ref object of RootObj
    textDocument*: TextDocumentItem

  DidChangeTextDocumentParams* = ref object of RootObj
    textDocument*: VersionedTextDocumentIdentifier
    contentChanges*: seq[TextDocumentContentChangeEvent]

  TextDocumentContentChangeEvent* = ref object of RootObj
    text*: string
    range*: Option[Range]
    rangeLength*: Option[int]

  TextDocumentChangeRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    syncKind*: int

  WillSaveTextDocumentParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    reason*: int

  DidSaveTextDocumentParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    text*: Option[string]

  TextDocumentSaveRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    includeText*: Option[bool]

  DidCloseTextDocumentParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier

  PublishDiagnosticsParams* = ref object of RootObj
    uri*: string
    diagnostics*: OptionalSeq[Diagnostic]

  CompletionParams* = ref object of TextDocumentPositionParams
    context*: Option[CompletionContext]

  CompletionContext* = ref object of RootObj
    triggerKind*: int
    triggerCharacter*: Option[string]

  CompletionList* = ref object of RootObj
    isIncomplete*: bool
    items*: OptionalSeq[CompletionItem]

  CompletionItemLabelDetails* = ref object of RootObj
    detail*: string
    description*: Option[string]

  CompletionItem* = ref object of RootObj
    label*: string
    labelDetails*: Option[CompletionItemLabelDetails]
    kind*: Option[int]
    tags*: OptionalSeq[int]
    detail*: Option[string]
    documentation*: OptionalNode #Option[string or MarkupContent]
    deprecated*: Option[bool]
    preselect*: Option[bool]
    sortText*: Option[string]
    filterText*: Option[string]
    insertText*: Option[string]
    insertTextFormat*: Option[int]
    textEdit*: Option[TextEdit]
    additionalTextEdits*: OptionalSeq[TextEdit]
    commitCharacters*: OptionalSeq[string]
    command*: Option[Command]
    data*: OptionalNode

  CompletionRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    triggerCharacters*: OptionalSeq[string]
    resolveProvider*: Option[bool]

  MarkedStringOption* = ref object of RootObj
    language*: string
    value*: string

  Hover* = ref object of RootObj
    contents*: OptionalNode # string or MarkedStringOption or [string] or [MarkedStringOption] or MarkupContent
    range*: Option[Range]

  HoverParams* = ref object of TextDocumentPositionParams

  SignatureHelp* = ref object of RootObj
    signatures*: seq[SignatureInformation]
    activeSignature*: Option[int]
    activeParameter*: Option[int]

  SignatureInformation* = ref object of RootObj
    label*: string
    documentation*: OptionalNode # string | MarkupContent
    parameters*: OptionalSeq[ParameterInformation]

  ParameterInformation* = ref object of RootObj
    label*: OptionalNode # string | seq[int]
    documentation*: OptionalNode # string | MarkupContent

  SignatureHelpRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    workDoneToken*: OptionalNode # ProgressToken
    triggerCharacters*: OptionalSeq[string]
    retriggerCharacters*: OptionalSeq[string]

  ReferenceParams* = ref object of TextDocumentPositionParams
    context*: ReferenceContext

  ReferenceContext* = ref object of RootObj
    includeDeclaration*: bool

  DocumentHighlight* = ref object of RootObj
    `range`*: Range
    kind*: Option[int]

  DocumentSymbolParams* = ref object of WorkDoneProgressParams
    partialResultToken*: OptionalNode # ProgressToken
    textDocument*: TextDocumentIdentifier

  DocumentSymbol* = ref object of RootObj
    name*: string
    detail*: Option[string]
    kind*: int # SymbolKind
    tags*: Option[seq[SymbolTag]]
    deprecated*: Option[bool]
    range*: Option[Range]
    selectionRange*: Option[Range]
    children*: Option[seq[DocumentSymbol]]

  SymbolInformation* = ref object of RootObj
    name*: string
    kind*: int # SymbolKind
    tags*: Option[seq[SymbolTag]]
    deprecated*: Option[bool]
    location*: Location
    containerName*: Option[string]

  CodeActionParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    `range`*: Range
    context*: CodeActionContext

  CodeActionContext* = ref object of RootObj
    diagnostics*: OptionalSeq[Diagnostic]

  CodeLensParams* = ref object of WorkDoneProgressParams
    partialResultToken*: OptionalNode # ProgressToken
    textDocument*: TextDocumentIdentifier

  CodeLens* = ref object of RootObj
    `range`*: Range
    command*: Option[Command]
    data*: OptionalNode

  CodeLensRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    workDoneProgress*: Option[bool]
    resolveProvider*: Option[bool]

  CodeLensWorkspaceClientCapabilities* = ref object of RootObj
    refreshSupport*: Option[bool]

  DocumentLinkParams* = ref object of WorkDoneProgressParams
    partialResultToken*: OptionalNode # ProgressToken
    textDocument*: TextDocumentIdentifier

  DocumentLink* = ref object of RootObj
    `range`*: Range
    target*: Option[string]
    tooltip*: Option[string]
    data*: OptionalNode

  DocumentLinkRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    resolveProvider*: Option[bool]

  DocumentColorParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier

  ColorInformation* = ref object of RootObj
    `range`*: Range
    color*: Color

  Color* = ref object of RootObj
    red*: int
    green*: int
    blue*: int
    alpha*: int

  ColorPresentationParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    color*: Color
    `range`*: Range

  ColorPresentation* = ref object of RootObj
    label*: string
    textEdit*: Option[TextEdit]
    additionalTextEdits*: OptionalSeq[TextEdit]

  FormattingOptions* = ref object of RootObj
    tabSize*: int
    insertSpaces*: bool
    trimTrailingWhitespace*: Option[bool]
    insertFinalNewline*: Option[bool]
    trimFinalNewlines*: Option[bool]

  DocumentFormattingParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    options*: FormattingOptions

  DocumentRangeFormattingParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    `range`*: Range
    options*: OptionalNode

  DocumentOnTypeFormattingParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    position*: Position
    ch*: string
    options*: OptionalNode

  DocumentOnTypeFormattingRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    firstTriggerCharacter*: string
    moreTriggerCharacter*: OptionalSeq[string]

  RenameParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    position*: Position
    newName*: string

  PrepareRenameParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    position*: Position

  PrepareRenameResponse* = ref object of RootObj
    defaultBehaviour*: bool

  SignatureHelpContext* = ref object of RootObj
    triggerKind*: int
    triggerCharacter*: Option[string]
    isRetrigger*: bool
    activeSignatureHelp*: Option[SignatureHelp]

  SignatureHelpParams* = ref object of TextDocumentPositionParams
    context*: SignatureHelpContext

  ExpandResult* = ref object of RootObj
    range*: Range
    content*: string

  PartialResultParams* = ref object of RootObj
    partialResultToken*: OptionalNode # ProgressToken

  SemanticTokensParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    workDoneToken*: OptionalNode # ProgressToken
    partialResultToken*: OptionalNode # ProgressToken

  SemanticTokensDeltaParams* = ref object of SemanticTokensParams
    previousResultId*: string

  SemanticTokens* = ref object of RootObj
    resultId*: Option[string]
    data*: seq[int]

  InlayHintParams* = ref object of RootObj # TODO: extends WorkDoneProgressParams
    textDocument*: TextDocumentIdentifier
    range*: Range

  InlayHint* = ref object of RootObj
    position*: Position
    label*: string  # string | InlayHintLabelPart[]
    kind*: Option[int]
    textEdits*: OptionalSeq[TextEdit]
    tooltip*: Option[string]  # string | MarkupContent
    paddingLeft*: Option[bool]
    paddingRight*: Option[bool]
    #data*: OptionalNode

  InlineValueContext* = ref object of RootObj
    frameId*: int
    stoppedLocation*: Range

  InlineValueParams* = ref object of WorkDoneProgressParams
    textDocument*: TextDocumentIdentifier
    range*: Range
    context*: InlineValueContext

  InlineValueText* = ref object of RootObj
    range*: Range
    text*: string

  InlineValueVariableLookup* = ref object of RootObj
    range*: Range
    variableName*: Option[string]
    caseSensitiveLookup: bool

  InlineValueEvaluatableExpression* = ref object of RootObj
    range: Range
    expression: Option[string]

  DefinitionParams* = ref object of TextDocumentPositionParams
    workDoneToken*: OptionalNode # ProgressToken
    workDoneProgress*: Option[bool]

  TypeDefinitionParams* = ref object of TextDocumentPositionParams
    workDoneToken*: OptionalNode # ProgressToken
    partialResultToken*: OptionalNode # ProgressToken

  ImplementationParams* = ref object of TextDocumentPositionParams
    workDoneToken*: OptionalNode # ProgressToken
    partialResultToken*: OptionalNode # ProgressToken

  CallHierarchyPrepareParams* = ref object of TextDocumentPositionParams
    workDoneToken*: OptionalNode # ProgressToken

  CallHierarchyItem* = ref object of RootObj
    name*: string
    kind*: int
    tags*: OptionalSeq[SymbolTag]
    detail*: Option[string]
    uri*: string
    range*: Range
    selectionRange*: Range
    data*: OptionalNode # unknown

  CallHierarchyIncomingCallsParams* = ref object of WorkDoneProgressParams
    partialResultToken*: OptionalNode # ProgressToken
    item*:  CallHierarchyItem

  CallHierarchyIncomingCall* = ref object of RootObj
    `from`*: CallHierarchyItem
    fromRanges*: seq[Range]

  CallHierarchyOutgoingCallsParams* = ref object of WorkDoneProgressParams
    partialResultToken*: OptionalNode # ProgressToken
    item*:  CallHierarchyItem

  CallHierarchyOutgoingCall* = ref object of RootObj
    to*: CallHierarchyItem
    fromRanges*: seq[Range]

  DocumentHighlightParams* = ref object of TextDocumentPositionParams
    workDoneProgress*: Option[bool]
    partialResultToken*: OptionalNode # ProgressToken

  FoldingRangeParams* = ref object of WorkDoneProgressParams
    partialResultToken*: OptionalNode # ProgressToken
    textDocument*: TextDocumentIdentifier

  FoldingRange* = ref object of RootObj
    startLine*: uint
    starCharacter*: Option[uint]
    endLine*: uint
    endCharacter*: Option[uint]
    kind*: Option[FoldingRangeKind]
    collapsedText*: Option[string]

  SelectionRangeParams* = ref object of WorkDoneProgressParams
    textDocument*: TextDocumentIdentifier
    positions*: seq[Position]

  SelectionRange* = ref object of RootObj
    range*: Range
    parent*: Option[SelectionRange]
