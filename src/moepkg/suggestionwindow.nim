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

import std/[sugar, options, sequtils, strutils, algorithm]
import ui, window, autocomplete, bufferstatus, gapbuffer, color,
       unicodeext, osext, popupwindow, commandline, fileutils, independentutils
import syntax/highlite

# TODO: Move to exmode.nim or exmodeutils.nim
const exCommandList: array[67, tuple[command, description: string]] = [
  (command: "!", description: "                    | Shell command execution"),
  (command: "deleteParen", description: "          | Enable/Disable auto delete paren"),
  (command: "b", description: "                    | Change the buffer with the given number"),
  (command: "bd", description: "                   | Delete the current buffer"),
  (command: "bg", description: "                   | Pause the editor and show the recent terminal output"),
  (command: "bfirst", description: "               | Change the first buffer"),
  (command: "blast", description: "                | Change the last buffer"),
  (command: "bnext", description: "                | Change the next buffer"),
  (command: "bprev", description: "                | Change the previous buffer"),
  (command: "build", description: "                | Build the current buffer"),
  (command: "buildOnSave", description: "          | Enable/Disable build on save"),
  (command: "buf", description: "                  | Open the buffer manager"),
  (command: "clipboard", description: "            | Enable/Disable accessing the system clipboard"),
  (command: "conf", description: "                 | Open the configuration mode"),
  (command: "cursorLine", description: "           | Change setting to the cursorLine"),
  (command: "cws", description: "                  | Create the work space"),
  (command: "debug", description: "                | Open the debug mode"),
  (command: "deleteTrailingSpaces", description: " | Delete the trailing spaces in the current buffer"),
  (command: "dws", description: "                  | Delete the current workspace"),
  (command: "e", description: "                    | Open file"),
  (command: "ene", description: "                  | Create the empty buffer"),
  (command: "help", description: "                 | Open the help"),
  (command: "highlightCurrentLine", description: " | Change setting to the highlightCurrentLine"),
  (command: "highlightCurrentWord", description: " | Change setting to the highlightCurrentWord"),
  (command: "highlightFullSpace", description: "   | Change setting to the highlightFullSpace"),
  (command: "highlightParen", description: "       | Change setting to the highlightParen"),
  (command: "backup", description: "               | Open the Backup file manager"),
  (command: "icon", description: "                 | Show/Hidden icons in filer mode"),
  (command: "ignorecase", description: "           | Change setting to ignore case in search"),
  (command: "incrementalSearch", description: "    | Enable/Disable incremental search"),
  (command: "indent", description: "               | Enable/Disable auto indent"),
  (command: "indentationLines", description: "     | Enable/Disable auto indentation lines"),
  (command: "linenum", description: "              | Enable/Disable the line number"),
  (command: "liveReload", description: "           | Enable/Disable the live reload of the config file"),
  (command: "log", description: "                  | Open the log viewer"),
  (command: "ls", description: "                   | Show the all buffer"),
  (command: "lsw", description: "                  | Show the all workspace"),
  (command: "man", description: "                  | Show the given UNIX manual page, if available"),
  (command: "multipleStatusLine", description: "   | Enable/Disable multiple status line"),
  (command: "new", description: "                  | Create the new buffer in split window horizontally"),
  (command: "noh", description: "                  | Turn off highlights"),
  (command: "paren", description: "                | Enable/Disable auto close paren"),
  (command: "putConfigFile", description: "        | Put the sample configuration file in ~/.config/moe"),
  (command: "q", description: "                    | Close the current window"),
  (command: "Q", description: "                    | Run Quickrun"),
  (command: "q!", description: "                   | Force close the current window"),
  (command: "qa", description: "                   | Close the all window in current workspace"),
  (command: "qa!", description: "                  | Force close the all window in current workspace"),
  (command: "recent", description: "               | Open the recent file selection mode"),
  (command: "run", description: "                  | run Quickrun"),
  (command: "scrollSpeed", description: "          | Change setting to the scroll speed"),
  (command: "showGitInactive", description: "      | Change status line setting to show/hide git branch name in inactive window"),
  (command: "smartcase", description: "            | Change setting to smart case in search"),
  (command: "smoothScroll", description: "         | Enable/Disable the smooth scroll"),
  (command: "sp", description: "                   | Open the file in horizontal split window"),
  (command: "statusLine", description: "           | Enable/Disable the status line"),
  (command: "syntax", description: "               | Enable/Disable the syntax highlighting"),
  (command: "tab", description: "                  | Enable/Disable the tab line"),
  (command: "tabstop", description: "              | Change setting to the tabstop"),
  (command: "theme", description: "                | Change the color theme"),
  (command: "vs", description: "                   | Vertical split window"),
  (command: "w", description: "                    | Write file"),
  (command: "w!", description: "                   | Force write file"),
  (command: "ws", description: "                   | Change the current workspace"),
  (command: "wq", description: "                   | Write file and close window"),
  (command: "wq!", description: "                  | Force write file and close window"),
  (command: "wqa", description: "                  | Write all file in current workspace")
]

type
  SuggestType* = enum
    text
    filePath
    exCommand
    exCommandOption

  SuggestionWindow* = object
    wordDictionary: WordDictionary
    oldLine: seq[Rune]
    inputWord: seq[Rune]
    firstColumn, lastColumn: int
    suggestoins: seq[seq[Rune]]
    selectedSuggestion: int
    popUpWindow: Option[Window]
    suggestType: SuggestType

proc isText(t: SuggestType): bool {.inline.} =
  t == SuggestType.text

proc isPath(t: SuggestType): bool {.inline.} =
  t == SuggestType.filePath

proc isExCommand(t: SuggestType): bool {.inline.} =
  t == SuggestType.exCommand

proc isExCommandOption(t: SuggestType): bool {.inline.} =
  t == SuggestType.exCommandOption

proc selectedWordOrInputWord(suggestionWindow: SuggestionWindow): seq[Rune] =
  if suggestionWindow.selectedSuggestion == -1:
    suggestionWindow.inputWord
  else:
    suggestionWindow.suggestoins[suggestionWindow.selectedSuggestion]

proc isPath(suggestWin: SuggestionWindow): bool {.inline.} =
  suggestWin.suggestType == SuggestType.filePath

proc newLine*(suggestionWindow: SuggestionWindow): seq[Rune] =
  if suggestionWindow.oldLine.len > 0:
    suggestionWindow.oldLine.dup(
      proc (r: var seq[Rune]) =
        let
          firstColumn = suggestionWindow.firstColumn
          lastColumn = suggestionWindow.lastColumn
        r[firstColumn .. lastColumn] =
          if suggestionWindow.isPath and r.len > 0 and r[firstColumn] == '/'.ru:
            "/".ru & suggestionWindow.selectedWordOrInputWord
          else:
            suggestionWindow.selectedWordOrInputWord)
  else:
    suggestionWindow.selectedWordOrInputWord

proc close*(suggestionWindow: var SuggestionWindow) =
  suggestionWindow.popUpWindow.get.deleteWindow
  suggestionWindow.popupwindow = none(Window)

proc canHandleInSuggestionWindow*(key: Rune): bool {.inline.} =
  isTabKey(key) or
  isShiftTab(key) or
  isUpKey(key) or
  isDownKey(key) or
  isPageUpKey(key) or
  isPageDownKey(key)

proc handleKeyInSuggestionWindow*(
  suggestionWindow: var SuggestionWindow,
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  key: Rune) =

    when not defined(release):
      doAssert(canHandleInSuggestionWindow(key))

    # Check whether the selected suggestion is changed.
    let prevSuggestion = suggestionWindow.selectedSuggestion

    if isTabKey(key) or isDownKey(key):
      if suggestionWindow.selectedSuggestion == suggestionWindow.suggestoins.high:
        suggestionWindow.selectedSuggestion = 0
      else:
        inc(suggestionWindow.selectedSuggestion)
    elif isShiftTab(key) or isUpKey(key):
      if suggestionWindow.selectedSuggestion == 0:
        suggestionWindow.selectedSuggestion = suggestionWindow.suggestoins.high
      else:
        dec(suggestionWindow.selectedSuggestion)
    elif isPageDownKey(key):
      suggestionWindow.selectedSuggestion +=
        suggestionWindow.popUpWindow.get.height - 1
    elif isPageUpKey(key):
      suggestionWindow.selectedSuggestion -=
        suggestionWindow.popUpWindow.get.height - 1

    suggestionWindow.selectedSuggestion =
      suggestionWindow.selectedSuggestion.clamp(0, suggestionWindow.suggestoins.high)

    if suggestionWindow.selectedSuggestion != prevSuggestion:
      # The selected suggestoin is changed.
      # Update the buffer without recording the change.
      let newLine = suggestionWindow.newLine
      bufStatus.buffer.assign(newLine, windowNode.currentLine, false)

      let
        firstColumn =
          if (suggestionWindow.isPath) and (newLine in '/'.ru):
            suggestionWindow.firstColumn + 1
          else:
            suggestionWindow.firstColumn
        wordLen = suggestionWindow.selectedWordOrInputWord.len
      windowNode.currentColumn = firstColumn + wordLen

      bufStatus.isUpdate = true

proc handleKeyInSuggestionWindow*(
  suggestionWindow: var SuggestionWindow,
  commandLine: var CommandLine,
  key: Rune) =

    when not defined(release):
      doAssert(canHandleInSuggestionWindow(key))

    # Check whether the selected suggestion is changed.
    let prevSuggestion = suggestionWindow.selectedSuggestion

    if isTabKey(key) or isDownKey(key):
      if suggestionWindow.selectedSuggestion == suggestionWindow.suggestoins.high:
        suggestionWindow.selectedSuggestion = 0
      else:
        inc(suggestionWindow.selectedSuggestion)
    elif isShiftTab(key) or isUpKey(key):
      if suggestionWindow.selectedSuggestion == 0:
        suggestionWindow.selectedSuggestion = suggestionWindow.suggestoins.high
      else:
        dec(suggestionWindow.selectedSuggestion)
    elif isPageDownKey(key):
      suggestionWindow.selectedSuggestion +=
        suggestionWindow.popUpWindow.get.height - 1
    elif isPageUpKey(key):
      suggestionWindow.selectedSuggestion -=
        suggestionWindow.popUpWindow.get.height - 1

    suggestionWindow.selectedSuggestion =
      suggestionWindow.selectedSuggestion.clamp(0, suggestionWindow.suggestoins.high)

    if suggestionWindow.selectedSuggestion != prevSuggestion:
      # The selected suggestoin is changed.
      # Update the buffer.
      suggestionWindow.oldLine.add ru" "
      let newLine = suggestionWindow.newLine
      commandLine.buffer = newLine

      let
        firstColumn = suggestionWindow.firstColumn
        wordLen = suggestionWindow.selectedWordOrInputWord.len
      commandLine.setBufferPositionX(firstColumn + wordLen)

## Suggestions are extracted from `text`.
## `word` is the inputted text.
## `isPath` is true when the file path suggestions.
proc initSuggestionWindow*(
  wordDictionary: var WordDictionary,
  text, word, currentLineText: seq[Rune],
  firstColumn, lastColumn: int,
  suggestType: SuggestType): Option[SuggestionWindow] =

    if not suggestType.isPath:
      wordDictionary.addWordToDictionary(text)

    let suggestoins =
      if suggestType == SuggestType.text:
        collectSuggestions(wordDictionary, word)
      else:
        text.splitWhitespace

    if suggestoins.len > 0:
      return SuggestionWindow(
        wordDictionary: wordDictionary,
        oldLine: currentLineText,
        inputWord: word,
        firstColumn: firstColumn,
        lastColumn: lastColumn,
        suggestoins: suggestoins,
        selectedSuggestion: -1,
        suggestType: suggestType
      ).some

proc extractWordBeforeCursor(
  bufStatus: BufferStatus,
  windowNode: WindowNode): Option[tuple[word: seq[Rune], first, last: int]] =

    if windowNode.currentColumn - 1 < 0: return

    extractNeighborWord(
      bufStatus.buffer[windowNode.currentLine],
      windowNode.currentColumn - 1)

proc extractPathBeforeCursor(
  bufStatus: BufferStatus,
  windowNode: WindowNode): Option[tuple[path: seq[Rune], first, last: int]] =

    if windowNode.currentColumn - 1 < 0: return

    extractNeighborPath(
      bufStatus.buffer[windowNode.currentLine],
      windowNode.currentColumn - 1)

proc extractWordBeforeCursor(
  commandLine: CommandLine): Option[tuple[word: seq[Rune], first, last: int]] =

    if commandLine.buffer.len > 0:
      let position = commandLine.bufferPosition
      return extractNeighborWord(
        commandLine.buffer,
        position.x - 1)

proc wordExistsBeforeCursor(
  bufStatus: BufferStatus,
  windowNode: WindowNode): bool =

    if windowNode.currentColumn == 0: return false

    let wordFirstLast = bufStatus.extractWordBeforeCursor(windowNode)
    wordFirstLast.isSome and wordFirstLast.get.word.len > 0

# Get a text in the buffer and language keywords
proc getBufferAndLangKeyword(
  checkBuffers: seq[BufferStatus],
  firstDeletedIndex, lastDeletedIndex: int,
  lang: SourceLanguage): seq[Rune] =

    let
      bufferText = getTextInBuffers(
        checkBuffers,
        firstDeletedIndex,
        lastDeletedIndex)
      keywordsText = getTextInLangKeywords(lang)

    return bufferText & keywordsText

## Build a suggestion window for editor (insert) mode.
proc buildSuggestionWindow*(
  bufStatus: seq[BufferStatus],
  wordDictionary: var WordDictionary,
  currentBufferIndex: int,
  root, currenWindowNode: WindowNode): Option[SuggestionWindow] =

    let
      currentBufStatus = bufStatus[currentBufferIndex]
      currentLineBuffer = currentBufStatus.buffer[currenWindowNode.currentLine]

      # Whether the word on the current position is a path.
      head = currentLineBuffer[0 .. currenWindowNode.currentColumn - 1]
      word = (head.splitWhitespace)[^1].removePrefix("\"".ru)
      suggestType =
        if word.isPath: SuggestType.filePath
        else: SuggestType.text

    if suggestType.isPath:
      let
        (path, firstColumn, lastColumn) = extractPathBeforeCursor(
          currentBufStatus,
          currenWindowNode).get

        (pathHead, pathTail) = splitPathExt(path)

        text = getPathList(path)

        # TODO: Fix and refactor
        first =
          if pathHead.high >= 0: firstColumn + pathHead.high
          else: 0
        last =
          if pathTail.len == 0: first
          else: lastColumn

      initSuggestionWindow(
        wordDictionary,
        text,
        pathTail,
        currentBufStatus.buffer[currenWindowNode.currentLine],
        first,
        last,
        suggestType)

    else:
      let
        currentBufStatus = bufStatus[currentBufferIndex]
        (word, firstColumn, lastColumn) = extractWordBeforeCursor(
          currentBufStatus,
          currenWindowNode).get

        # Eliminate the word on the cursor.
        line = currenWindowNode.currentLine
        column = firstColumn
        firstDeletedIndex = currentBufStatus.buffer.calcIndexInEntireBuffer(
          line,
          column,
          true)
        lastDeletedIndex = firstDeletedIndex + word.len - 1
        bufferIndexList = root.getAllBufferIndex

      # 0 is current bufStatus
      var checkBuffers: seq[BufferStatus] = @[bufStatus[currentBufferIndex]]
      for i in bufferIndexList:
        if i != currentBufferIndex: checkBuffers.add bufStatus[i]

      let text = getBufferAndLangKeyword(
        checkBuffers,
        firstDeletedIndex,
        lastDeletedIndex,
        bufStatus[currentBufferIndex].language)

      initSuggestionWindow(
        wordDictionary,
        text,
        word,
        currentBufStatus.buffer[currenWindowNode.currentLine],
        firstColumn,
        lastColumn,
        suggestType)

# TODO: Move to exmode?
proc isExCommand(buffer: string): bool =
  let bufferSplited = strutils.splitWhitespace(buffer)
  if bufferSplited.len > 0:
    for c in exCommandList:
      if bufferSplited[0] == c.command:
        return true

# TODO: Move to unicodeext?
proc removeSuffix(r: seq[Runes], suffix: string): seq[Runes] =
  for i in 0 .. r.high:
    var string = $r[i]
    string.removeSuffix(suffix)
    if i == 0: result = @[string.toRunes]
    else: result.add(string.toRunes)

proc splitQout(s: string): seq[Runes]=
  result = @[ru""]
  var
    quotIn = false
    backSlash = false

  for i in 0 .. s.high:
    if s[i] == '\\':
      backSlash = true
    elif backSlash:
      backSlash = false
      result[result.high].add(($s[i]).toRunes)
    elif i > 0 and s[i - 1] == '\\':
      result[result.high].add(($s[i]).toRunes)
    elif not quotIn and s[i] == '"':
      quotIn = true
      result.add(ru"")
    elif quotIn and s[i] == '"':
      quotIn = false
      if i != s.high:  result.add(ru"")
    else:
      result[result.high].add(($s[i]).toRunes)

  return result.removeSuffix(" ")

proc splitCommand(command: string): seq[Runes] =
  if (command).contains('"'):
    return splitQout(command)
  else:
    return strutils.splitWhitespace(command).mapIt(it.toRunes)

proc getSuggestType(buffer: Runes): SuggestType =
  proc isECommand(command: seq[Runes]): bool {.inline.} =
    cmpIgnoreCase($command[0], "e") == 0

  proc isVsCommand(command: seq[Runes]): bool {.inline.} =
    cmpIgnoreCase($command[0], "vs") == 0

  proc isSvCommand(command: seq[Runes]): bool {.inline.} =
    cmpIgnoreCase($command[0], "sv") == 0

  proc isSpCommand(command: seq[Runes]): bool {.inline.} =
    command.len > 0 and
    command.len < 3 and
    cmpIgnoreCase($command[0], "sp") == 0


  if buffer.len > 0 and isExCommand($buffer):
    let cmd = splitCommand($buffer)
    if isECommand(cmd) or
       isVsCommand(cmd) or
       isSvCommand(cmd) or
       isSpCommand(cmd): SuggestType.filePath
    else:
      SuggestType.exCommandOption
  else:
    SuggestType.exCommand

proc isSuggestTypeExCommand*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommand

proc isSuggestTypeExCommandOption*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.exCommandOption

proc isSuggestTypeFilePath*(suggestType: SuggestType): bool {.inline.} =
  suggestType == SuggestType.filePath

proc firstArg(buffer: Runes): Runes =
  let commandSplit = splitWhitespace(buffer)
  if commandSplit.len > 0:
    return commandSplit[0]
  else:
    return "".toRunes

## Return a path in the `buffer`.
## Return an absolute path if path is `~`.
proc getInputPath*(buffer: Runes): Runes =
  let bufferSplited = strutils.splitWhitespace($buffer)
  if bufferSplited.len > 1:
    # Assume the last word as path.
    let path = bufferSplited[^1]

    if path == "~":
      return getHomeDir().toRunes
    else:
      return path.toRunes

proc getCandidatesExCommand*(commandLineBuffer: Runes): seq[Runes] =
  let buffer = toLowerAscii($commandLineBuffer)
  for list in exCommandList:
    let cmd = list.command
    if cmd.len >= buffer.len and cmd.startsWith(buffer):
      result.add(cmd.toRunes)

## Return file paths for a suggestion from `buffer`.
## Return all file and dir in the current dir if inputPath is empty.
proc getCandidatesFilePath*(buffer: Runes): seq[string] =
  let inputPath = buffer.getInputPath

  var list: seq[Runes] = @[]

  # result[0] is input
  result.add $inputPath

  if inputPath.contains(ru'/'):
    let
      normalizedInput = normalizePath(inputPath)
      normalizedPath = normalizePath(inputPath.substr(0, inputPath.rfind(ru'/')))
    for kind, path in walkDir($normalizedPath):
      if path.toRunes.len > normalizedInput.len and
            path.toRunes.startsWith(normalizedInput):
        if inputPath[0] == ru'~':
          let
            pathLen = path.toRunes.high
            hoemeDirLen = (getHomeDir()).high
            addPath = ru"~" & path.toRunes.substr(hoemeDirLen, pathLen)
            # If the path is a directory, add '/'
            p = if dirExists($addPath): addPath & ru "/" else: addPath
          list.add(p)
        else:
          # If the path is a directory, add '/'
          let p = if dirExists(path): path & "/" else: path
          list.add(p.toRunes)
  else:
    for kind, path in walkDir("./"):
      let normalizePath = path.toRunes.normalizePath
      if inputPath.len == 0 or normalizePath.startsWith(inputPath):
        let p = path.toRunes.normalizePath
        # If the path is a directory, add '/'
        if dirExists($p): list.add p & ru "/"
        else: list.add p

  for path in list: result.add($path)
  result.sort(proc (a, b: string): int = cmp(a, b))

proc getCandidatesExCommandOption*(commandLine: CommandLine): seq[Runes] =
  let
    buffer = commandLine.buffer
    command = $buffer.firstArg

  var argList: seq[string] = @[]
  case toLowerAscii(command):
    of "cursorline",
       "highlightparen",
       "indent",
       "linenum",
       "livereload",
       "realtimesearch",
       "statusline",
       "syntax",
       "tabstop",
       "smoothscroll",
       "clipboard",
       "highlightCurrentLine",
       "highlightcurrentword",
       "highlightfullspace",
       "multiplestatusline",
       "buildonsave",
       "indentationlines",
       "icon",
       "showgitinactive",
       "ignorecase",
       "smartcase":
         argList = @["on", "off"]
    of "theme":
      argList = @["vivid", "dark", "light", "config", "vscode"]
    of "e",
       "sp",
       "vs",
       "sv":
         argList = buffer.getCandidatesFilePath
    else:
      discard

  if argList.len > 0 and argList[0] != "":
    let arg =
      if splitWhitespace(buffer).len > 1:
        splitWhitespace(buffer)[1]
      else:
        ru""
    result = @[arg]

  for i in 0 ..< argList.len:
    result.add(argList[i].toRunes)

proc getSuggestList(
  commandLine: CommandLine,
  suggestType: SuggestType): seq[Runes] =

    if isSuggestTypeExCommand(suggestType):
      result = getCandidatesExCommand(commandLine.buffer)
    elif isSuggestTypeExCommandOption(suggestType):
      result = commandLine.getCandidatesExCommandOption
    else:
      let pathList = commandLine.buffer.getCandidatesFilePath
      for path in pathList: result.add(path.ru)

proc calcXWhenSuggestPath*(buffer, inputPath: Runes): int =
  let
    # TODO: Refactor
    positionInInputPath =
      if inputPath.len > 0 and
         (inputPath.count('/'.toRune) > 1 or
         (not inputPath.startsWith("./".toRunes)) or
         (inputPath.count('/'.toRune) == 1 and $inputPath[^1] != "/")):
           inputPath.rfind(ru"/")
      else:
        0

  const promptAndSpaceWidth = 2
  let command = buffer.firstArg
  return command.len + promptAndSpaceWidth + positionInInputPath

## Build a suggestion window for the command line.
proc buildSuggestionWindow*(
  commandLine: CommandLine,
  wordDictionary: var WordDictionary): Option[SuggestionWindow] =

    let
      suggestType = commandLine.buffer.getSuggestType
      suggestList = commandLine.getSuggestList(suggestType)

      wordFirstLast = commandLine.extractWordBeforeCursor

      word =
        if wordFirstLast.isSome: wordFirstLast.get.word
        else: ru""

      firstColumn =
        if wordFirstLast.isSome: wordFirstLast.get.first
        else: commandLine.bufferPositionX

      lastColumn =
        if wordFirstLast.isSome: wordFirstLast.get.last
        else: firstColumn

    initSuggestionWindow(
      wordDictionary,
      suggestList.join,
      word,
      commandLine.buffer,
      firstColumn,
      lastColumn,
      suggestType)

## Return a `SuggestionWindow` for a text being edited if it's possible to create.
## Return `None` if no candidates exist.
proc tryOpenSuggestionWindow*(
  bufStatus: seq[BufferStatus],
  wordDictionary: var WordDictionary,
  currentBufferIndex: int,
  root, currenWindowNode: WindowNode): Option[SuggestionWindow] =

    if wordExistsBeforeCursor(bufStatus[currentBufferIndex], currenWindowNode):
      return bufStatus.buildSuggestionWindow(
        wordDictionary,
        currentBufferIndex,
        root,
        currenWindowNode)

## Return a `SuggestionWindow` for the command line if it's possible to create.
## Return `None` if no candidates exist.
proc tryOpenSuggestionWindow*(
  commandLine: CommandLine,
  wordDictionary: var WordDictionary): Option[SuggestionWindow] =

    return commandLine.buildSuggestionWindow(wordDictionary)

## Return the absolute suggestion window position.
proc calcSuggestionWindowPosition*(
  windowNode: WindowNode,
  mainWindowHeight: int,
  suggestionWindow: SuggestionWindow): Position =

    let
      line = windowNode.currentLine
      column = suggestionWindow.firstColumn
      (absoluteY, absoluteX) = windowNode.absolutePosition(line, column)
      diffY = 1
      leftMargin = 1

      # If the suggest window height is higher than the main window height under the cursor position,
      # the suggest window  move to over the cursor position
      suggestHigh = suggestionWindow.suggestoins.high
      y =
        if suggestHigh > (mainWindowHeight - absoluteY - diffY) and
          absoluteY > (mainWindowHeight - absoluteY):
          max(absoluteY - suggestHigh - diffY, 0)
        else:
          absoluteY + diffY

      x =
        if suggestionWindow.isPath and suggestionWindow.oldLine.count('/'.ru) > 1:
          absoluteX - leftMargin + 1
        else:
          absoluteX - leftMargin

    return Position(x: x, y: y)

## Return the absolute suggestion window position.
proc calcSuggestionWindowPosition*(
  commandLine: CommandLine,
  suggestionWindow: SuggestionWindow): Position =

    let
      suggestHigh = suggestionWindow.suggestoins.high
      x = commandLine.prompt.len + suggestionWindow.inputWord.len
      y =
        if suggestHigh > (getTerminalHeight() - 1 - commandLine.windowSize.h):
          getTerminalHeight() - 1 - commandLine.windowSize.h
        else:
          getTerminalHeight() - 1 - commandLine.windowSize.h - suggestHigh

    Position(x: x, y: y)

## cursorPosition is absolute y
proc calcMaxSugestionWindowHeight(
  y: int,
  cursorYPosition: int,
  mainWindowNodeY: int,
  isEnableStatusLine: bool): int =

    const commanLineHeight = 1
    let statusLineHeight = if isEnableStatusLine: 1 else: 0

    if y > cursorYPosition:
      result = (getTerminalHeight() - 1) - cursorYPosition - commanLineHeight - statusLineHeight
    else:
      result = cursorYPosition - mainWindowNodeY

## Write (Update) a suggestion window for main windows.
proc writeSuggestionWindow*(
  windowNode: WindowNode,
  mainWindowNodeY: int,
  suggestionWindow: var SuggestionWindow,
  position: Position,
  isEnableStatusLine: bool) =

    let
      line = windowNode.currentLine
      column = windowNode.currentColumn
      (absoluteY, _) = windowNode.absolutePosition(line, column)
      # TODO: Calc maxHeight when calculating the window position. Remove from here.
      maxHeight = calcMaxSugestionWindowHeight(
        position.y,
        absoluteY,
        mainWindowNodeY,
        isEnableStatusLine)
      height = min(suggestionWindow.suggestoins.len, maxHeight)
      width = suggestionWindow.suggestoins.map(item => item.len).max + 2

    if suggestionWindow.popUpWindow.isNone:
      let y =
        if position.y < mainWindowNodeY: mainWindowNodeY
        else: position.y
      suggestionWindow.popUpWindow = initWindow(
        height,
        width,
        y,
        position.x,
        EditorColorPair.popUpWindow
      )
      .some
    else:
      suggestionWindow.popUpWindow.get.height = height
      suggestionWindow.popUpWindow.get.width = width
      suggestionWindow.popUpWindow.get.y = position.y
      suggestionWindow.popUpWindow.get.x = position.x

    let currentLine =
      if suggestionWindow.selectedSuggestion == -1: none(int)
      else: suggestionWindow.selectedSuggestion.some

    suggestionWindow.popUpWindow.get.writePopUpWindow(
      suggestionWindow.popUpWindow.get.height,
      suggestionWindow.popUpWindow.get.width,
      suggestionWindow.popUpWindow.get.y,
      suggestionWindow.popUpWindow.get.x,
      currentLine,
      suggestionWindow.suggestoins)

## Write (Update) a suggestion window for the command line.
proc writeSuggestionWindow*(
  commandLine: CommandLine,
  suggestionWindow: var SuggestionWindow,
  position: Position) =

    let
      # TODO: Calc maxHeight when calculating the window position. Remove from here.
      maxHeight = getTerminalHeight() - 1
      height = min(suggestionWindow.suggestoins.len, maxHeight)
      width = suggestionWindow.suggestoins.map(item => item.len).max + 2

    if suggestionWindow.popUpWindow.isNone:
      suggestionWindow.popUpWindow = initWindow(
        height,
        width,
        position.y,
        position.x,
        EditorColorPair.popUpWindow
      )
      .some
    else:
      suggestionWindow.popUpWindow.get.height = height
      suggestionWindow.popUpWindow.get.width = width
      suggestionWindow.popUpWindow.get.y = position.y
      suggestionWindow.popUpWindow.get.x = position.x

    let currentLine =
      if suggestionWindow.selectedSuggestion == -1: none(int)
      else: suggestionWindow.selectedSuggestion.some

    suggestionWindow.popUpWindow.get.writePopUpWindow(
      suggestionWindow.popUpWindow.get.height,
      suggestionWindow.popUpWindow.get.width,
      suggestionWindow.popUpWindow.get.y,
      suggestionWindow.popUpWindow.get.x,
      currentLine,
      suggestionWindow.suggestoins)

proc isLineChanged*(suggestionWindow: SuggestionWindow): bool {.inline.} =
  suggestionWindow.newLine != suggestionWindow.oldLine

proc getSelectedWord*(suggestionWindow: SuggestionWindow): seq[Rune] {.inline.} =
  if suggestionWindow.selectedSuggestion >= 0:
    return suggestionWindow.suggestoins[suggestionWindow.selectedSuggestion]
