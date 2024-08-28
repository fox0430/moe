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

import std/tables

import ui, unicodeext

type
  NormlaModeCommand* = enum
    enterExMode
    enterSearchForwardMode
    enterSearchBackwardMode
    moveNextWindow
    movePrevWindow
    enterVisualBlockMode
    moveCursorLeft
    moveCursorRight
    moveCursorUp
    moveCursorDown
    deleteCharacter
    cutCharacterBeforeCursor
    moveFirstNonBlankOfLine
    moveFirstOfLine
    moveLastOfLine
    moveFirstOfPrevLine
    moveFirstOfNextLine
    movePrevBlankLine
    moveNextBlankLine
    moveFirstLine
    moveLastNonBlankOfLine
    showCharacterInfo
    gotoDeclaration
    gotoDefinition
    gotoTypeDefinition
    gotoImplementation
    findReferences
    callHierarchy
    documentLink
    moveLastLine
    halfPageUp
    halfPageDown
    pageUp
    pageDown
    moveWordForward
    moveWordBackward
    moveEndOfWordForward
    scrollScreenCenter
    scrollScreenTop
    scrollScreenBottom
    removeFoldLine
    removeAllFoldLine
    moveTopOfScreen
    moveCenterOfScreen
    moveBottomOfScreen
    moveMatchBracket
    openBlankLineBelowAndEnterInsertMode
    openBlankLineAboveAndEnterInsertMode
    deleteCharacterAfterBlankInLine
    deleteAllInLineAndEnterInsertMode
    deleteCharacterAndEnterInsertMode
    changeInner
    changeForward
    changeUntil
    deleteLine
    deleteWord
    deleteToEndOfLine
    deleteToStartOfLine
    deleteLineToLastLine
    deleteLineToFirstLine
    deleteToPrevBlankLine
    deleteToNextBlankLine
    deleteInner
    cutBeforeCursor
    deleteCharactersUntil
    yankLine
    yankWord
    yankToPrevBlankLine
    yankToNextBlankLine
    yankCharacter
    yankToFirstOfLine
    yankToEndOfLine
    yankUntillCharacter
    pasteAfter
    pasteBefore
    indent
    unindent
    autoIndent
    joinLine
    incNumber
    decNumber
    toggleCaseAndMoveRight
    replaceCharacter
    nextOccurrence
    prevOccurrence
    nextOccurrenceCurrentWord
    prevOccurrenceCurrentWord
    moveNextCharacterInLine
    moveNextCharacterUntilInLine
    movePrevCharacterInLine
    movePrevCharacterUntilInLine
    enterReplaceMode
    enterInsertMode
    moveToBeginOfLineAndEnterInsertMode
    enterVisualMode
    enterVisualLineMode
    enterInsertModeAfterCursor
    moveToEndOfLineAndEnterInsertMode
    undo
    redo
    writeAndQuit
    forceQuit
    closeWindow
    quickRun
    codeLens
    register
    recordMacro
    stopRecordMacro
    hover
    rename
    repeatLastAction

  NormalModeKeyBindings* = TableRef[seq[Key], seq[NormlaModeCommand]]

proc defaultNormalModeKeyBindings*(): NormalModeKeyBindings =
  {
    ":".toKeys: @[enterExMode],
    "/".toKeys: @[enterSearchForwardMode],
    "?".toKeys: @[enterSearchBackwardMode],
    CtrlK.toKeys: @[moveNextWindow],
    CtrlJ.toKeys: @[movePrevWindow],
    CtrlV.toKeys: @[enterVisualBlockMode],
    "h".toKeys: @[moveCursorLeft],
    LeftKey.toKeys: @[moveCursorLeft],
    BackSpaceKey.toKeys: @[moveCursorLeft],
    "l".toKeys: @[moveCursorRight],
    RightKey.toKeys: @[moveCursorRight],
    "k".toKeys: @[moveCursorUp],
    UpKey.toKeys: @[moveCursorUp],
    "j".toKeys: @[moveCursorDown],
    DownKey.toKeys: @[moveCursorDown],
    "x".toKeys: @[deleteCharacter],
    "X".toKeys: @[cutCharacterBeforeCursor],
    "^".toKeys: @[moveFirstNonBlankOfLine],
    "_".toKeys: @[moveFirstNonBlankOfLine],
    "0".toKeys: @[moveFirstOfLine],
    HomeKey.toKeys: @[moveFirstOfLine],
    "$".toKeys: @[moveLastOfLine],
    EndKey.toKeys: @[moveLastOfLine],
    "-".toKeys: @[moveFirstOfPrevLine],
    "+".toKeys: @[moveFirstOfNextLine],
    "{".toKeys: @[movePrevBlankLine],
    "}".toKeys: @[moveNextBlankLine],
    "gg".toKeys: @[moveFirstLine],
    "g_".toKeys: @[moveLastNonBlankOfLine],
    "ga".toKeys: @[showCharacterInfo],
    "gc".toKeys: @[gotoDeclaration],
    "gd".toKeys: @[gotoDefinition],
    "gy".toKeys: @[gotoTypeDefinition],
    "gi".toKeys: @[gotoImplementation],
    "gr".toKeys: @[findReferences],
    "gh".toKeys: @[callHierarchy],
    "dl".toKeys: @[documentLink],
    "G".toKeys: @[moveLastLine],
    CtrlU.toKeys: @[halfPageUp],
    CtrlD.toKeys: @[halfPageDown],
    PageUpKey.toKeys: @[pageUp],
    PageDownKey.toKeys: @[pageDown],
    "w".toKeys: @[moveWordForward],
    "b".toKeys: @[moveWordBackward],
    "e".toKeys: @[moveEndOfWordForward],
    "z.".toKeys: @[scrollScreenCenter],
    "zt".toKeys: @[scrollScreenTop],
    "zb".toKeys: @[scrollScreenBottom],
    "zd".toKeys: @[removeFoldLine],
    "zD".toKeys: @[removeAllFoldLine],
    "H".toKeys: @[moveTopOfScreen],
    "M".toKeys: @[moveCenterOfScreen],
    "L".toKeys: @[moveBottomOfScreen],
    "%".toKeys: @[moveMatchBracket],
    "o".toKeys: @[openBlankLineBelowAndEnterInsertMode],
    "O".toKeys: @[openBlankLineAboveAndEnterInsertMode],
    "S".toKeys: @[deleteAllInLineAndEnterInsertMode],
    "cc".toKeys: @[deleteAllInLineAndEnterInsertMode],
    "s".toKeys: @[deleteCharacterAndEnterInsertMode],
    "cl".toKeys: @[deleteCharacterAndEnterInsertMode],
    "ci".toKeys: @[changeInner],
    "cf".toKeys: @[changeForward],
    "ct".toKeys: @[changeUntil],
    "dd".toKeys: @[deleteLine],
    "dw".toKeys: @[deleteWord],
    "D".toKeys: @[deleteToEndOfLine],
    "d$".toKeys: @[deleteToEndOfLine],
    @['d'.Key, EndKey.Key]: @[deleteToEndOfLine],
    "d0".toKeys: @[deleteToStartOfLine],
    @['d'.Key, HomeKey.Key]: @[deleteToStartOfLine],
    "dG".toKeys: @[deleteLineToLastLine],
    "dgg".toKeys: @[deleteLineToFirstLine],
    "d{".toKeys: @[deleteToPrevBlankLine],
    "d}".toKeys: @[deleteToNextBlankLine],
    "di".toKeys: @[deleteInner],
    "dh".toKeys: @[cutBeforeCursor],
    "dt".toKeys: @[deleteCharactersUntil],
    "Y".toKeys: @[yankLine],
    "yy".toKeys: @[yankLine],
    "yw".toKeys: @[yankWord],
    "y{".toKeys: @[yankToPrevBlankLine],
    "y}".toKeys: @[yankToNextBlankLine],
    "yl".toKeys: @[yankCharacter],
    "y0".toKeys: @[yankToFirstOfLine],
    "y$".toKeys: @[yankToEndOfLine],
    "yt".toKeys: @[yankUntillCharacter],
    "p".toKeys: @[pasteAfter],
    "P".toKeys: @[pasteBefore],
    ">".toKeys: @[indent],
    "<".toKeys: @[unindent],
    "==".toKeys: @[autoIndent],
    "J".toKeys: @[joinLine],
    CtrlA.toKeys: @[incNumber],
    CtrlX.toKeys: @[decNumber],
    "~".toKeys: @[toggleCaseAndMoveRight],
    "r".toKeys: @[replaceCharacter],
    "n".toKeys: @[nextOccurrence],
    "N".toKeys: @[prevOccurrence],
    "*".toKeys: @[nextOccurrenceCurrentWord],
    "#".toKeys: @[prevOccurrenceCurrentWord],
    "f".toKeys: @[moveNextCharacterInLine],
    "t".toKeys: @[moveNextCharacterUntilInLine],
    "F".toKeys: @[movePrevCharacterInLine],
    "T".toKeys: @[movePrevCharacterUntilInLine],
    "R".toKeys: @[enterReplaceMode],
    "i".toKeys: @[enterInsertMode],
    "I".toKeys: @[moveToBeginOfLineAndEnterInsertMode],
    "v".toKeys: @[enterVisualMode],
    "V".toKeys: @[enterVisualLineMode],
    "a".toKeys: @[enterInsertModeAfterCursor],
    "A".toKeys: @[moveToEndOfLineAndEnterInsertMode],
    "r".toKeys: @[undo],
    CtrlR.toKeys: @[redo],
    "ZZ".toKeys: @[writeAndQuit],
    "ZQ".toKeys: @[forceQuit],
    @[CtrlW.Key, 'c'.Key]: @[closeWindow],
    "\\r".toKeys: @[quickRun],
    "\\c".toKeys: @[codeLens],
    "\"".toKeys: @[register],
    "q".toKeys: @[recordMacro],
    "q".toKeys: @[stopRecordMacro],
    "K".toKeys: @[hover],
    " r".toKeys: @[rename],
    ".".toKeys: @[repeatLastAction]
  }
  .newTable
