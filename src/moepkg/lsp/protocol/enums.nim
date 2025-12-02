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

## LSP Protocol Enumerations
## Based on LSP Specification 3.17

type
  DiagnosticSeverity* = enum
    ## Diagnostic severity levels
    dsError = 1
    dsWarning = 2
    dsInformation = 3
    dsHint = 4

  CompletionItemKind* = enum
    ## Completion item kinds
    cikText = 1
    cikMethod = 2
    cikFunction = 3
    cikConstructor = 4
    cikField = 5
    cikVariable = 6
    cikClass = 7
    cikInterface = 8
    cikModule = 9
    cikProperty = 10
    cikUnit = 11
    cikValue = 12
    cikEnum = 13
    cikKeyword = 14
    cikSnippet = 15
    cikColor = 16
    cikFile = 17
    cikReference = 18
    cikFolder = 19
    cikEnumMember = 20
    cikConstant = 21
    cikStruct = 22
    cikEvent = 23
    cikOperator = 24
    cikTypeParameter = 25

  SymbolKind* = enum
    ## Symbol kinds for document symbols
    skFile = 1
    skModule = 2
    skNamespace = 3
    skPackage = 4
    skClass = 5
    skMethod = 6
    skProperty = 7
    skField = 8
    skConstructor = 9
    skEnum = 10
    skInterface = 11
    skFunction = 12
    skVariable = 13
    skConstant = 14
    skString = 15
    skNumber = 16
    skBoolean = 17
    skArray = 18
    skObject = 19
    skKey = 20
    skNull = 21
    skEnumMember = 22
    skStruct = 23
    skEvent = 24
    skOperator = 25
    skTypeParameter = 26

  MessageType* = enum
    ## Message types for window/showMessage
    mtError = 1
    mtWarning = 2
    mtInfo = 3
    mtLog = 4

  TextDocumentSyncKind* = enum
    ## How documents are synced to the server
    tdskNone = 0
    tdskFull = 1
    tdskIncremental = 2

  CompletionTriggerKind* = enum
    ## How a completion was triggered
    ctkInvoked = 1
    ctkTriggerCharacter = 2
    ctkTriggerForIncompleteCompletions = 3

  InsertTextFormat* = enum
    ## Format of the insert text
    itfPlainText = 1
    itfSnippet = 2

  DiagnosticTag* = enum
    ## Diagnostic tags for additional information
    dtUnnecessary = 1
    dtDeprecated = 2

  MarkupKind* = enum
    ## Markup content kind
    mkPlainText = "plaintext"
    mkMarkdown = "markdown"

  ErrorCodes* = enum
    ## JSON-RPC error codes
    ecParseError = -32700
    ecInvalidRequest = -32600
    ecMethodNotFound = -32601
    ecInvalidParams = -32602
    ecInternalError = -32603
    # LSP specific
    ecServerNotInitialized = -32002
    ecUnknownErrorCode = -32001
    ecRequestFailed = -32803
    ecServerCancelled = -32802
    ecContentModified = -32801
    ecRequestCancelled = -32800
