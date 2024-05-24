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
    id*: OptionalNode

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

  ExecuteCommandCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  WorkspaceClientCapabilities* = ref object of RootObj
    applyEdit*: Option[bool]
    workspaceEdit*: Option[WorkspaceEditCapability]
    didChangeConfiguration*: Option[DidChangeConfigurationCapability]
    didChangeWatchedFiles*: Option[DidChangeWatchedFilesCapability]
    symbol*: Option[SymbolCapability]
    executeCommand*: Option[ExecuteCommandCapability]
    workspaceFolders*: Option[bool]
    configuration*: Option[bool]

  SynchronizationCapability* = ref object of RootObj
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

  CompletionCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    completionItem*: Option[CompletionItemCapability]
    completionItemKind*: Option[CompletionItemKindCapability]
    contextSupport*: Option[bool]

  HoverCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    contentFormat*: OptionalSeq[string]

  SignatureInformationCapability* = ref object of RootObj
    documentationFormat*: OptionalSeq[string]

  SignatureHelpCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    signatureInformation*: Option[SignatureInformationCapability]

  ReferencesCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DocumentHighlightCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DocumentSymbolCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    symbolKind*: Option[SymbolKindCapability]

  FormattingCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  RangeFormattingCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  OnTypeFormattingCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DefinitionCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  TypeDefinitionCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  ImplementationCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  CodeActionCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  CodeLensCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  DocumentLinkCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  ColorProviderCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]

  RenameCapability* = ref object of RootObj
    dynamicRegistration*: Option[bool]
    prepareSupport*: Option[bool]

  PublishDiagnosticsCapability* = ref object of RootObj
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

  TextDocumentClientCapabilities* = ref object of RootObj
    synchronization*: Option[SynchronizationCapability]
    completion*: Option[CompletionCapability]
    hover*: Option[HoverCapability]
    signatureHelp*: Option[SignatureHelpCapability]
    references*: Option[ReferencesCapability]
    documentHighlight*: Option[DocumentHighlightCapability]
    documentSymbol*: Option[DocumentSymbolCapability]
    formatting*: Option[FormattingCapability]
    rangeFormatting*: Option[RangeFormattingCapability]
    onTypeFormatting*: Option[OnTypeFormattingCapability]
    definition*: Option[DefinitionCapability]
    typeDefinition*: Option[TypeDefinitionCapability]
    implementation*: Option[ImplementationCapability]
    codeAction*: Option[CodeActionCapability]
    codeLens*: Option[CodeLensCapability]
    documentLink*: Option[DocumentLinkCapability]
    colorProvider*: Option[ColorProviderCapability]
    rename*: Option[RenameCapability]
    publishDiagnostics*: Option[PublishDiagnosticsCapability]
    semanticTokens*: Option[SemanticTokensClientCapabilities]
    inlayHint*: Option[InlayHintClientCapabilities]

  WindowCapabilities* = ref object of RootObj
    workDoneProgress*: Option[bool]
    showMessage*: Option[ShowMessageRequestParams]
    showDocument*: Option[ShowDocumentClientCapabilities]

  ClientCapabilities* = ref object of RootObj
    workspace*: Option[WorkspaceClientCapabilities]
    textDocument*: Option[TextDocumentClientCapabilities]
    window*: Option[WindowCapabilities]
    # experimental*: OptionalNode

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

  SignatureHelpOptions* = ref object of RootObj
    triggerCharacters*: OptionalSeq[string]

  CodeLensOptions* = ref object of RootObj
    resolveProvider*: Option[bool]

  DocumentOnTypeFormattingOptions* = ref object of RootObj
    firstTriggerCharacter*: string
    moreTriggerCharacter*: OptionalSeq[string]

  DocumentLinkOptions* = ref object of RootObj
    resolveProvider*: Option[bool]

  ExecuteCommandOptions* = ref object of RootObj
   commands*: OptionalSeq[string]

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

  RenameOptions* = object
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

  InlayHintOptions* = object
    resolveProvider*: Option[bool]

  DiagnosticOptions* = ref object of WorkDoneProgressOptions
    identifier*: Option[string]
    interFileDependencies*: bool
    workspaceDiagnostics*: bool

  DiagnosticRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    identifier*: Option[string]
    interFileDependencies*: bool
    workspaceDiagnostics*: bool
    id*: Option[string]

  ServerCapabilities* = ref object of RootObj
    textDocumentSync*: OptionalNode # TextDocumentSyncOptions or int
    hoverProvider*: Option[bool]
    completionProvider*: Option[CompletionOptions]
    signatureHelpProvider*: SignatureHelpOptions
    definitionProvider*: Option[bool]
    declarationProvider*: Option[bool]
    typeDefinitionProvider*: Option[bool]
    implementationProvider*: OptionalNode # bool or TextDocumentAndStaticRegistrationOptions
    referencesProvider*: Option[bool]
    documentHighlightProvider*: Option[bool]
    documentSymbolProvider*: Option[bool]
    workspaceSymbolProvider*: Option[bool]
    codeActionProvider*: Option[bool]
    codeLensProvider*: Option[CodeLensOptions]
    documentFormattingProvider*: Option[bool]
    documentRangeFormattingProvider*: Option[bool]
    documentOnTypeFormattingProvider*: Option[DocumentOnTypeFormattingOptions]
    renameProvider*: OptionalNode # bool or RenameOptions
    documentLinkProvider*: Option[DocumentLinkOptions]
    colorProvider*: OptionalNode # bool or ColorProviderOptions | TextDocumentAndStaticRegistrationOptions
    executeCommandProvider*: Option[ExecuteCommandOptions]
    workspace*: Option[WorkspaceCapability]
    semanticTokensProvider*: OptionalNode # SemanticTokensOptions or SemanticTokensRegistrationOptions
    inlayHintProvider*: Option[InlayHintOptions]  # boolean | InlayHintOptions | InlayHintRegistrationOptions
    diagnosticProvider*: OptionalNode # DiagnosticOptions | DiagnosticRegistrationOptions
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

  ExecuteCommandParams* = ref object of RootObj
    command*: string
    arguments*: seq[JsonNode]

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
    signatures*: OptionalSeq[SignatureInformation]
    activeSignature*: Option[int]
    activeParameter*: Option[int]

  SignatureInformation* = ref object of RootObj
    label*: string
    documentation*: Option[string or MarkupContent]
    parameters*: OptionalSeq[ParameterInformation]

  ParameterInformation* = ref object of RootObj
    label*: string
    documentation*: Option[string or MarkupContent]

  SignatureHelpRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    triggerCharacters*: OptionalSeq[string]

  ReferenceParams* = ref object of TextDocumentPositionParams
    context*: ReferenceContext

  ReferenceContext* = ref object of RootObj
    includeDeclaration*: bool

  DocumentHighlight* = ref object of RootObj
    `range`*: Range
    kind*: Option[int]

  DocumentSymbolParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier

  SymbolInformation* = ref object of RootObj
    name*: string
    kind*: int
    deprecated*: Option[bool]
    location*: Location
    containerName*: Option[string]

  CodeActionParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    `range`*: Range
    context*: CodeActionContext

  CodeActionContext* = ref object of RootObj
    diagnostics*: OptionalSeq[Diagnostic]

  CodeLensParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier

  CodeLens* = ref object of RootObj
    `range`*: Range
    command*: Option[Command]
    data*: OptionalNode

  CodeLensRegistrationOptions* = ref object of TextDocumentRegistrationOptions
    resolveProvider*: Option[bool]

  DocumentLinkParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier

  DocumentLink* = ref object of RootObj
    `range`*: Range
    target*: Option[string]
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

  DocumentFormattingParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    options*: OptionalNode

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
    activeSignatureHelp*: SignatureHelp

  SignatureHelpParams* = ref object of TextDocumentPositionParams
    context*: SignatureHelpContext

  ExpandResult* = ref object of RootObj
    range*: Range
    content*: string

  SemanticTokensParams* = ref object of RootObj
    textDocument*: TextDocumentIdentifier
    workDoneToken*: OptionalNode # int or string (ProgressToken)
    partialResultToken*: OptionalNode # int or string (ProgressToken)

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

  DefinitionParams* = ref object of TextDocumentPositionParams
    workDoneToken*: OptionalNode # ProgressToken
    workDoneProgress*: Option[bool]
