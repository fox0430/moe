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

import std/unittest

import ../src/moepkg/lsp/protocol/enums

suite "enums - DiagnosticSeverity":
  test "dsError is 1":
    check dsError.int == 1

  test "dsWarning is 2":
    check dsWarning.int == 2

  test "dsInformation is 3":
    check dsInformation.int == 3

  test "dsHint is 4":
    check dsHint.int == 4

suite "enums - CompletionItemKind":
  test "cikText is 1":
    check cikText.int == 1

  test "cikMethod is 2":
    check cikMethod.int == 2

  test "cikFunction is 3":
    check cikFunction.int == 3

  test "cikClass is 7":
    check cikClass.int == 7

  test "cikModule is 9":
    check cikModule.int == 9

  test "cikKeyword is 14":
    check cikKeyword.int == 14

  test "cikSnippet is 15":
    check cikSnippet.int == 15

  test "cikTypeParameter is 25":
    check cikTypeParameter.int == 25

suite "enums - SymbolKind":
  test "skFile is 1":
    check skFile.int == 1

  test "skModule is 2":
    check skModule.int == 2

  test "skClass is 5":
    check skClass.int == 5

  test "skFunction is 12":
    check skFunction.int == 12

  test "skVariable is 13":
    check skVariable.int == 13

  test "skTypeParameter is 26":
    check skTypeParameter.int == 26

suite "enums - MessageType":
  test "mtError is 1":
    check mtError.int == 1

  test "mtWarning is 2":
    check mtWarning.int == 2

  test "mtInfo is 3":
    check mtInfo.int == 3

  test "mtLog is 4":
    check mtLog.int == 4

suite "enums - TextDocumentSyncKind":
  test "tdskNone is 0":
    check tdskNone.int == 0

  test "tdskFull is 1":
    check tdskFull.int == 1

  test "tdskIncremental is 2":
    check tdskIncremental.int == 2

suite "enums - CompletionTriggerKind":
  test "ctkInvoked is 1":
    check ctkInvoked.int == 1

  test "ctkTriggerCharacter is 2":
    check ctkTriggerCharacter.int == 2

  test "ctkTriggerForIncompleteCompletions is 3":
    check ctkTriggerForIncompleteCompletions.int == 3

suite "enums - InsertTextFormat":
  test "itfPlainText is 1":
    check itfPlainText.int == 1

  test "itfSnippet is 2":
    check itfSnippet.int == 2

suite "enums - DiagnosticTag":
  test "dtUnnecessary is 1":
    check dtUnnecessary.int == 1

  test "dtDeprecated is 2":
    check dtDeprecated.int == 2

suite "enums - MarkupKind":
  test "mkPlainText string value":
    check $mkPlainText == "plaintext"

  test "mkMarkdown string value":
    check $mkMarkdown == "markdown"

suite "enums - InlayHintKind":
  test "ihkType is 1":
    check ihkType.int == 1

  test "ihkParameter is 2":
    check ihkParameter.int == 2

suite "enums - DocumentHighlightKind":
  test "dhkText is 1":
    check dhkText.int == 1

  test "dhkRead is 2":
    check dhkRead.int == 2

  test "dhkWrite is 3":
    check dhkWrite.int == 3

suite "enums - FoldingRangeKind":
  test "frkComment string value":
    check $frkComment == "comment"

  test "frkImports string value":
    check $frkImports == "imports"

  test "frkRegion string value":
    check $frkRegion == "region"

suite "enums - SemanticTokenTypes":
  test "sttNamespace string value":
    check $sttNamespace == "namespace"

  test "sttFunction string value":
    check $sttFunction == "function"

  test "sttKeyword string value":
    check $sttKeyword == "keyword"

  test "sttComment string value":
    check $sttComment == "comment"

  test "sttString string value":
    check $sttString == "string"

suite "enums - SemanticTokenModifiers":
  test "stmDeclaration string value":
    check $stmDeclaration == "declaration"

  test "stmDefinition string value":
    check $stmDefinition == "definition"

  test "stmReadonly string value":
    check $stmReadonly == "readonly"

  test "stmDeprecated string value":
    check $stmDeprecated == "deprecated"
