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

## LSP Service Layer
## Manages multiple LSP clients and provides high-level API for editor integration

import std/[tables, options, os, strutils, json]

import pkg/results

import lsp/client
import lsp/protocol/types

export client
export types

type
  LanguageServerConfig* = object ## Configuration for a language server
    command*: string
    args*: seq[string]
    extensions*: seq[string]
    enabled*: bool

  LspService* = ref object ## Service for managing LSP clients
    clients: Table[string, LspClient] # languageId -> client
    configs: Table[string, LanguageServerConfig] # languageId -> config
    workspaceRoot: string
    enabled*: bool
    # Global callbacks (forwarded from individual clients)
    onDiagnosticsUpdate*: proc(uri: string, diagnostics: seq[Diagnostic])
    onLogMessage*: proc(langId: string, msgType: MessageType, message: string)

proc newLspService*(workspaceRoot: string = ""): LspService =
  ## Create a new LSP service
  result = LspService(
    clients: initTable[string, LspClient](),
    configs: initTable[string, LanguageServerConfig](),
    workspaceRoot:
      if workspaceRoot.len > 0:
        workspaceRoot
      else:
        getCurrentDir(),
    enabled: true,
    onDiagnosticsUpdate: nil,
    onLogMessage: nil,
  )

  # Default language server configurations
  result.configs["nim"] = LanguageServerConfig(
    command: "nimlangserver",
    args: @[],
    extensions: @["nim", "nims", "nimble"],
    enabled: true,
  )

  result.configs["rust"] = LanguageServerConfig(
    command: "rust-analyzer", args: @[], extensions: @["rs"], enabled: true
  )

  result.configs["python"] = LanguageServerConfig(
    command: "pylsp", args: @[], extensions: @["py", "pyw"], enabled: true
  )

  result.configs["typescript"] = LanguageServerConfig(
    command: "typescript-language-server",
    args: @["--stdio"],
    extensions: @["ts", "tsx"],
    enabled: true,
  )

  result.configs["javascript"] = LanguageServerConfig(
    command: "typescript-language-server",
    args: @["--stdio"],
    extensions: @["js", "jsx", "mjs"],
    enabled: true,
  )

  result.configs["go"] = LanguageServerConfig(
    command: "gopls", args: @[], extensions: @["go"], enabled: true
  )

  result.configs["c"] = LanguageServerConfig(
    command: "clangd", args: @[], extensions: @["c", "h"], enabled: true
  )

  result.configs["cpp"] = LanguageServerConfig(
    command: "clangd",
    args: @[],
    extensions: @["cpp", "hpp", "cc", "hh", "cxx", "hxx"],
    enabled: true,
  )

proc setConfig*(svc: LspService, langId: string, config: LanguageServerConfig) =
  ## Set configuration for a language server
  svc.configs[langId] = config

proc getConfig*(svc: LspService, langId: string): Option[LanguageServerConfig] =
  ## Get configuration for a language server
  if langId in svc.configs:
    return some(svc.configs[langId])
  return none(LanguageServerConfig)

proc getLanguageIdFromPath*(svc: LspService, path: string): Option[string] =
  ## Determine language ID from file path extension
  let ext = path.splitFile().ext.strip(chars = {'.'}).toLowerAscii()
  if ext.len == 0:
    return none(string)

  for langId, config in svc.configs:
    if config.enabled and ext in config.extensions:
      return some(langId)

  return none(string)

proc getLanguageIdFromExtension*(svc: LspService, ext: string): Option[string] =
  ## Determine language ID from file extension
  let cleanExt = ext.strip(chars = {'.'}).toLowerAscii()

  for langId, config in svc.configs:
    if config.enabled and cleanExt in config.extensions:
      return some(langId)

  return none(string)

proc pathToUri*(path: string): string =
  ## Convert file path to URI
  if path.startsWith("file://"):
    return path
  return "file://" & path.absolutePath()

proc uriToPath*(uri: string): string =
  ## Convert URI to file path
  if uri.startsWith("file://"):
    return uri[7 ..^ 1]
  return uri

proc getClient*(svc: LspService, langId: string): Option[LspClient] =
  ## Get existing client for a language
  if langId in svc.clients:
    let client = svc.clients[langId]
    if client.isRunning:
      return some(client)
  return none(LspClient)

proc startClient*(svc: LspService, langId: string): Result[LspClient, string] =
  ## Start a client for a language (or return existing one)
  if not svc.enabled:
    return err("LSP service is disabled")

  # Check if client already running
  if langId in svc.clients:
    let client = svc.clients[langId]
    if client.isRunning:
      return ok(client)

  # Get config
  if langId notin svc.configs:
    return err("No LSP configuration for language: " & langId)

  let config = svc.configs[langId]
  if not config.enabled:
    return err("LSP disabled for language: " & langId)

  # Create new client
  let client = newLspClient(
    languageId = langId,
    command = config.command,
    args = config.args,
    workspaceRoot = svc.workspaceRoot,
  )

  # Set up callbacks
  let langIdCapture = langId
  client.onDiagnostics = proc(uri: string, diagnostics: seq[Diagnostic]) =
    if svc.onDiagnosticsUpdate != nil:
      svc.onDiagnosticsUpdate(uri, diagnostics)

  client.onLogMessage = proc(msgType: MessageType, message: string) =
    if svc.onLogMessage != nil:
      svc.onLogMessage(langIdCapture, msgType, message)

  # Start server
  let startResult = client.start()
  if startResult.isErr:
    return err(startResult.error)

  svc.clients[langId] = client
  return ok(client)

proc getOrStartClient*(svc: LspService, langId: string): Result[LspClient, string] =
  ## Get existing client or start a new one
  let existing = svc.getClient(langId)
  if existing.isSome:
    return ok(existing.get)
  return svc.startClient(langId)

proc getClientForPath*(svc: LspService, path: string): Result[LspClient, string] =
  ## Get or start client for a file path
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return err("No LSP support for file: " & path)
  return svc.getOrStartClient(langIdOpt.get)

proc stopClient*(svc: LspService, langId: string): Result[void, string] =
  ## Stop a client for a language
  if langId notin svc.clients:
    return ok()

  let client = svc.clients[langId]
  let stopResult = client.stop()
  svc.clients.del(langId)
  return stopResult

proc stopAll*(svc: LspService) =
  ## Stop all clients
  for langId, client in svc.clients:
    discard client.stop()
  svc.clients.clear()

proc poll*(svc: LspService, timeoutMs: int = 0) =
  ## Poll all running clients for messages
  for langId, client in svc.clients:
    if client.isRunning:
      discard client.poll(timeoutMs)

# High-level document operations
proc notifyDocumentOpened*(
    svc: LspService, path: string, text: string
): Result[void, string] =
  ## Notify that a document was opened
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.didOpen(uri, client.languageId, 1, text)

proc notifyDocumentChanged*(
    svc: LspService, path: string, version: int, text: string
): Result[void, string] =
  ## Notify that a document changed
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return ok() # No LSP for this file type

  let clientOpt = svc.getClient(langIdOpt.get)
  if clientOpt.isNone:
    return ok() # Client not started

  let client = clientOpt.get
  let uri = pathToUri(path)
  return client.didChange(uri, version, text)

proc notifyDocumentClosed*(svc: LspService, path: string): Result[void, string] =
  ## Notify that a document was closed
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return ok()

  let clientOpt = svc.getClient(langIdOpt.get)
  if clientOpt.isNone:
    return ok()

  let client = clientOpt.get
  let uri = pathToUri(path)
  return client.didClose(uri)

proc notifyDocumentSaved*(
    svc: LspService, path: string, text: Option[string] = none(string)
): Result[void, string] =
  ## Notify that a document was saved
  let langIdOpt = svc.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return ok()

  let clientOpt = svc.getClient(langIdOpt.get)
  if clientOpt.isNone:
    return ok()

  let client = clientOpt.get
  let uri = pathToUri(path)
  return client.didSave(uri, text)

# High-level feature requests
proc requestCompletion*(
    svc: LspService, path: string, line, character: int
): Result[seq[CompletionItem], string] =
  ## Request completion at a position
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.completion(uri, line, character)

proc requestHover*(
    svc: LspService, path: string, line, character: int
): Result[Option[Hover], string] =
  ## Request hover information at a position
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.hover(uri, line, character)

proc requestDefinition*(
    svc: LspService, path: string, line, character: int
): Result[seq[Location], string] =
  ## Request go to definition
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.gotoDefinition(uri, line, character)

proc requestDeclaration*(
    svc: LspService, path: string, line, character: int
): Result[seq[Location], string] =
  ## Request go to declaration
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.gotoDeclaration(uri, line, character)

proc requestTypeDefinition*(
    svc: LspService, path: string, line, character: int
): Result[seq[Location], string] =
  ## Request go to type definition
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.gotoTypeDefinition(uri, line, character)

proc requestImplementation*(
    svc: LspService, path: string, line, character: int
): Result[seq[Location], string] =
  ## Request go to implementation
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.gotoImplementation(uri, line, character)

proc requestReferences*(
    svc: LspService, path: string, line, character: int, includeDeclaration: bool = true
): Result[seq[Location], string] =
  ## Request references to a symbol
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.references(uri, line, character, includeDeclaration)

proc requestDocumentHighlight*(
    svc: LspService, path: string, line, character: int
): Result[seq[DocumentHighlight], string] =
  ## Request document highlights at a position
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.documentHighlight(uri, line, character)

proc requestDocumentLinks*(
    svc: LspService, path: string
): Result[seq[DocumentLink], string] =
  ## Request document links for a file
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.documentLink(uri)

proc requestDocumentLinkResolve*(
    svc: LspService, path: string, link: DocumentLink
): Result[DocumentLink, string] =
  ## Resolve a document link to get its target URI
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  return client.documentLinkResolve(link)

proc requestSignatureHelp*(
    svc: LspService, path: string, line, character: int
): Result[Option[SignatureHelp], string] =
  ## Request signature help at a position
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.signatureHelp(uri, line, character)

proc requestRename*(
    svc: LspService, path: string, line, character: int, newName: string
): Result[Option[WorkspaceEdit], string] =
  ## Request rename of a symbol
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.rename(uri, line, character, newName)

proc requestFormatting*(
    svc: LspService, path: string, tabSize: int = 2, insertSpaces: bool = true
): Result[seq[TextEdit], string] =
  ## Request document formatting
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.formatting(uri, tabSize, insertSpaces)

proc requestRangeFormatting*(
    svc: LspService,
    path: string,
    startLine, startChar, endLine, endChar: int,
    tabSize: int = 2,
    insertSpaces: bool = true,
): Result[seq[TextEdit], string] =
  ## Request range formatting
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.rangeFormatting(
    uri, startLine, startChar, endLine, endChar, tabSize, insertSpaces
  )

# Capability checking
proc hasCompletionSupport*(svc: LspService, langId: string): bool =
  ## Check if completion is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.completionProvider.isSome

proc hasHoverSupport*(svc: LspService, langId: string): bool =
  ## Check if hover is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.hoverProvider.isSome

proc hasDefinitionSupport*(svc: LspService, langId: string): bool =
  ## Check if go to definition is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.definitionProvider.isSome

proc hasDeclarationSupport*(svc: LspService, langId: string): bool =
  ## Check if go to declaration is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.declarationProvider.isSome

proc hasTypeDefinitionSupport*(svc: LspService, langId: string): bool =
  ## Check if go to type definition is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.typeDefinitionProvider.isSome

proc hasImplementationSupport*(svc: LspService, langId: string): bool =
  ## Check if go to implementation is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.implementationProvider.isSome

proc hasReferencesSupport*(svc: LspService, langId: string): bool =
  ## Check if find references is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.referencesProvider.isSome

proc hasDocumentHighlightSupport*(svc: LspService, langId: string): bool =
  ## Check if document highlight is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.documentHighlightProvider.isSome

proc hasDocumentLinkSupport*(svc: LspService, langId: string): bool =
  ## Check if document link is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.documentLinkProvider.isSome

proc hasDocumentLinkResolveSupport*(svc: LspService, langId: string): bool =
  ## Check if document link resolve is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  let provider = client.capabilities.get.documentLinkProvider
  if provider.isNone:
    return false

  # Check if resolveProvider is true in the provider options
  let providerNode = provider.get
  if providerNode.kind == JObject and providerNode.hasKey("resolveProvider"):
    return providerNode["resolveProvider"].getBool(false)

  return false

proc hasSignatureHelpSupport*(svc: LspService, langId: string): bool =
  ## Check if signature help is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.signatureHelpProvider.isSome

proc hasRenameSupport*(svc: LspService, langId: string): bool =
  ## Check if rename is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.renameProvider.isSome

proc hasFormattingSupport*(svc: LspService, langId: string): bool =
  ## Check if document formatting is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.documentFormattingProvider.isSome

proc hasRangeFormattingSupport*(svc: LspService, langId: string): bool =
  ## Check if range formatting is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.documentRangeFormattingProvider.isSome

proc hasDocumentSymbolSupport*(svc: LspService, langId: string): bool =
  ## Check if document symbol is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.documentSymbolProvider.isSome

proc requestDocumentSymbols*(
    svc: LspService, path: string
): Result[DocumentSymbolResult, string] =
  ## Request document symbols for a file
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.documentSymbol(uri)

proc hasInlayHintSupport*(svc: LspService, langId: string): bool =
  ## Check if inlay hints is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.inlayHintProvider.isSome

proc requestInlayHints*(
    svc: LspService, path: string, startLine, startChar, endLine, endChar: int
): Result[seq[InlayHint], string] =
  ## Request inlay hints for a range in a file
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.inlayHints(uri, startLine, startChar, endLine, endChar)

proc hasSemanticTokensSupport*(svc: LspService, langId: string): bool =
  ## Check if semantic tokens is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.semanticTokensProvider.isSome

proc hasSemanticTokensFullSupport*(svc: LspService, langId: string): bool =
  ## Check if full semantic tokens is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  let provider = client.capabilities.get.semanticTokensProvider
  if provider.isNone:
    return false

  return provider.get.full.isSome

proc hasSemanticTokensRangeSupport*(svc: LspService, langId: string): bool =
  ## Check if range semantic tokens is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  let provider = client.capabilities.get.semanticTokensProvider
  if provider.isNone:
    return false

  return provider.get.range.isSome

proc getSemanticTokensLegend*(
    svc: LspService, langId: string
): Option[SemanticTokensLegend] =
  ## Get the semantic tokens legend for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return none(SemanticTokensLegend)

  let client = clientOpt.get
  if client.capabilities.isNone:
    return none(SemanticTokensLegend)

  let provider = client.capabilities.get.semanticTokensProvider
  if provider.isNone:
    return none(SemanticTokensLegend)

  return some(provider.get.legend)

proc requestSemanticTokensFull*(
    svc: LspService, path: string
): Result[Option[SemanticTokens], string] =
  ## Request full semantic tokens for a file
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.semanticTokensFull(uri)

proc requestSemanticTokensRange*(
    svc: LspService, path: string, startLine, startChar, endLine, endChar: int
): Result[Option[SemanticTokens], string] =
  ## Request semantic tokens for a range in a file
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.semanticTokensRange(uri, startLine, startChar, endLine, endChar)

proc hasSelectionRangeSupport*(svc: LspService, langId: string): bool =
  ## Check if selection range is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.selectionRangeProvider.isSome

proc hasInlineValueSupport*(svc: LspService, langId: string): bool =
  ## Check if inline value is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.inlineValueProvider.isSome

proc requestSelectionRange*(
    svc: LspService, path: string, positions: seq[Position]
): Result[seq[SelectionRange], string] =
  ## Request selection ranges for given positions in a file
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.selectionRange(uri, positions)

proc requestSelectionRange*(
    svc: LspService, path: string, line, character: int
): Result[Option[SelectionRange], string] =
  ## Request selection range for a single position in a file
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.selectionRange(uri, line, character)

# Status information
proc getRunningLanguages*(svc: LspService): seq[string] =
  ## Get list of languages with running LSP servers
  for langId, client in svc.clients:
    if client.isRunning:
      result.add(langId)

proc getServerInfo*(svc: LspService, langId: string): Option[ServerInfo] =
  ## Get server information for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return none(ServerInfo)
  return clientOpt.get.serverInfo

proc requestInlineValues*(
    svc: LspService,
    path: string,
    startLine, startChar, endLine, endChar: int,
    frameId: int,
    stoppedLine, stoppedStartChar, stoppedEndLine, stoppedEndChar: int,
): Result[seq[InlineValue], string] =
  ## Request inline values for a range in a file during debugging
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.inlineValues(
    uri, startLine, startChar, endLine, endChar, frameId, stoppedLine, stoppedStartChar,
    stoppedEndLine, stoppedEndChar,
  )

# CodeLens support
proc hasCodeLensSupport*(svc: LspService, langId: string): bool =
  ## Check if code lens is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  return client.capabilities.get.codeLensProvider.isSome

proc hasCodeLensResolveSupport*(svc: LspService, langId: string): bool =
  ## Check if code lens resolve is supported for a language
  let clientOpt = svc.getClient(langId)
  if clientOpt.isNone:
    return false

  let client = clientOpt.get
  if client.capabilities.isNone:
    return false

  let provider = client.capabilities.get.codeLensProvider
  if provider.isNone:
    return false

  # Check if resolveProvider is true in the provider options
  let providerNode = provider.get
  if providerNode.kind == JObject and providerNode.hasKey("resolveProvider"):
    return providerNode["resolveProvider"].getBool(false)

  return false

proc requestCodeLens*(svc: LspService, path: string): Result[seq[CodeLens], string] =
  ## Request code lenses for a file
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  let uri = pathToUri(path)
  return client.codeLens(uri)

proc requestCodeLensResolve*(
    svc: LspService, path: string, lens: CodeLens
): Result[CodeLens, string] =
  ## Resolve a code lens to get its command
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  return client.codeLensResolve(lens)

proc requestExecuteCommand*(
    svc: LspService, path: string, command: string, arguments: seq[JsonNode] = @[]
): Result[JsonNode, string] =
  ## Execute a command on the LSP server
  let clientResult = svc.getClientForPath(path)
  if clientResult.isErr:
    return err(clientResult.error)

  let client = clientResult.get
  return client.executeCommand(command, arguments)
