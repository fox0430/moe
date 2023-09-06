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

import std/[strutils, sequtils]
import pkg/results
import unicodeext, bufferstatus

type
  ArgsType* {.pure.} = enum
    none
    toggle  # "on" or "off"
    number
    text
    path    # File path
    theme   # color.ColorTheme

  ExCommandInfo* = object
    command*: string
    description*: string
    argsType*: ArgsType

const
  ExCommandInfoList* = [
    ExCommandInfo(
    command: "!",
    description: "Shell command execution",
    argsType: ArgsType.text),
    ExCommandInfo(
      command: "deleteParen",
      description: "Enable/Disable auto delete paren",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "b",
      description: "Change the buffer with the given number",
      argsType: ArgsType.number),
    ExCommandInfo(
      command: "bd",
      description: "Delete the current buffer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "bg",
      description: "Pause the editor and show the recent terminal output",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "bfirst",
      description: "Change the first buffer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "blast",
      description: "Change the last buffer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "bnext",
      description: "Change the next buffer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "bprev",
      description: "Change the previous buffer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "build",
      description: "Build the current buffer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "buildOnSave",
      description: "Enable/Disable build on save",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "buf",
      description: "Open the buffer manager",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "clipboard",
      description: "Enable/Disable accessing the system clipboard",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "conf",
      description: "Open the configuration mode",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "cursorLine",
      description: "Change setting to the cursorLine",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "debug",
      description: "Open the debug mode",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "deleteTrailingSpaces",
      description: "Delete the trailing spaces in the current buffer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "e",
      description: "Open file",
      argsType: ArgsType.path),
    ExCommandInfo(
      command: "ene",
      description: "Create the empty buffer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "help",
      description: "Open the help",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "highlightCurrentLine",
      description: "Change setting to the highlightCurrentLine",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "highlightCurrentWord",
      description: "Change setting to the highlightCurrentWord",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "highlightFullSpace",
      description: "Change setting to the highlightFullSpace",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "highlightParen",
      description: "Change setting to the highlightParen",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "backup",
      description: "Open the Backup file manager",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "icon",
      description: "Show/Hidden icons in filer mode",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "ignorecase",
      description: "Change setting to ignore case in search",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "incrementalSearch",
      description: "Enable/Disable incremental search",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "indent",
      description: "Enable/Disable auto indent",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "indentationLines",
      description: "Enable/Disable auto indentation lines",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "linenum",
      description: "Enable/Disable the line number",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "liveReload",
      description: "Enable/Disable the live reload of the config file",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "log",
      description: "Open the log viewer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "ls",
      description: "Show the all buffer",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "man",
      description: "Show the given UNIX manual page, if available",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "multipleStatusLine",
      description: "Enable/Disable multiple status line",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "new",
      description: "Create the new buffer in split window horizontally",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "noh",
      description: "Turn off highlights",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "paren",
      description: "Enable/Disable auto close paren",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "putConfigFile",
      description: "Put the sample configuration file in ~/.config/moe",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "q",
      description: "Close the current window",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "Q",
      description: "Run Quickrun",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "q!",
      description: "Force close the current window",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "qa",
      description: "Close the all windows",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "qa!",
      description: "Force close the all windows",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "recent",
      description: "Open the recent file selection mode",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "run",
      description: "Run Quickrun",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "scrollMinDelay",
      description: "Change setting to the smooth scroll min delay",
      argsType: ArgsType.number),
    ExCommandInfo(
      command: "scrollMaxDelay",
      description: "Change setting to the smooth scroll max delay",
      argsType: ArgsType.number),
    ExCommandInfo(
      command: "showGitInactive",
      description: "Change status line setting to show/hide git branch name in inactive window",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "smartcase",
      description: "Change setting to smart case in search",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "smoothScroll",
      description: "Enable/Disable the smooth scroll",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "sp",
      description: "Open the file in horizontal split window",
      argsType: ArgsType.path),
    ExCommandInfo(
      command: "statusLine",
      description: "Enable/Disable the status line",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "syntax",
      description: "Enable/Disable the syntax highlighting",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "sv",
      description: "Horizontal split window",
      argsType: ArgsType.path),
    ExCommandInfo(
      command: "tab",
      description: "Enable/Disable the tab line",
      argsType: ArgsType.toggle),
    ExCommandInfo(
      command: "tabstop",
      description: "Change setting to the tabstop",
      argsType: ArgsType.number),
    ExCommandInfo(
      command: "theme",
      description: "Change the color theme",
      argsType: ArgsType.theme),
    ExCommandInfo(
      command: "vs",
      description: "Vertical split window",
      argsType: ArgsType.path),
    ExCommandInfo(
      command: "w",
      description: "Write file",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "w!",
      description: "Force write file",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "wq",
      description: "Write file and close window",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "wq!",
      description: "Force write file and close window",
      argsType: ArgsType.none),
    ExCommandInfo(
      command: "wqa",
      description: "Write all files",
      argsType: ArgsType.none)
  ]

when (NimMajor, NimMinor) >= (1, 9):
  # These codes can't compile in Nim 1.6. Maybe compiler bug.

  proc noArgsCommandList*(): seq[Runes] {.compileTime.} =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.none)
      .mapIt(it.command.toRunes)

  proc toggleArgsCommandList*(): seq[Runes] {.compileTime.} =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.toggle)
      .mapIt(it.command.toRunes)

  proc numberArgsCommandList*(): seq[Runes] {.compileTime.} =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.number)
      .mapIt(it.command.toRunes)

  proc textArgsCommandList*(): seq[Runes] {.compileTime.} =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.text)
      .mapIt(it.command.toRunes)

  proc pathArgsCommandList*(): seq[Runes] {.compileTime.} =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.path)
      .mapIt(it.command.toRunes)

  proc themeArgsCommandList*(): seq[Runes] {.compileTime.} =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.theme)
      .mapIt(it.command.toRunes)
else:
  proc noArgsCommandList*(): seq[Runes] =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.none)
      .mapIt(it.command.toRunes)

  proc toggleArgsCommandList*(): seq[Runes] =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.toggle)
      .mapIt(it.command.toRunes)

  proc numberArgsCommandList*(): seq[Runes] =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.number)
      .mapIt(it.command.toRunes)

  proc textArgsCommandList*(): seq[Runes] =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.text)
      .mapIt(it.command.toRunes)

  proc pathArgsCommandList*(): seq[Runes] =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.path)
      .mapIt(it.command.toRunes)

  proc themeArgsCommandList*(): seq[Runes] =
    ExCommandInfoList
      .filterIt(it.argsType == ArgsType.theme)
      .mapIt(it.command.toRunes)

proc exCommandList*(): array[ExCommandInfoList.len, Runes] {.compileTime.} =
  for i, info in ExCommandInfoList: result[i] = info.command.toRunes

proc lowerExCommandList*():
  array[ExCommandInfoList.len, Runes] {.compileTime.} =
    for i, info in ExCommandInfoList:
      result[i] = info.command.toLowerAscii.toRunes

proc splitExCommandBuffer*(rawInput: Runes): seq[Runes]=
  ## Split `runes` that consider single quotes and double quotes.

  if not rawInput.contains(ru'\'') and not rawInput.contains(ru'"'):
    return rawInput.splitWhitespace

  var
    inEscape = false
    inSingleQuot = false
    inDoubleQuot = false

  result = @[ru""]

  for r in rawInput:
    if inEscape:
      inEscape = false
      result[^1].add r
    elif not inEscape and r == ru'\\':
      inEscape = true
    elif not inEscape and r == ru'\'':
      if inSingleQuot:
        inSingleQuot = false
      elif not inDoubleQuot:
        inSingleQuot = true
        if result[^1].len > 0: result.add ru""
      else:
          result[^1].add r
    elif not inEscape and r == ru'\"':
      if inDoubleQuot:
        inDoubleQuot = false
      elif not inSingleQuot:
        inDoubleQuot = true
        if result[^1].len > 0: result.add ru""
      else:
        result[^1].add r
    elif not inSingleQuot and not inDoubleQuot and r.isWhiteSpace:
      result.add ru""
    else:
      result[^1].add r

proc isExCommand*(c: Runes, isCaseSensitive: bool = false): bool =
  if c.len > 0:
    if isCaseSensitive:
      return exCommandList().contains(c)
    else:
      return lowerExCommandList().contains(c.toLower)

proc isNoArgsCommand*(c: Runes, isCaseSensitive: bool = false): bool {.used.} =
  # NOTE: Remove the used pragma if you use this.

  if isCaseSensitive:
    noArgsCommandList().contains(c)
  else:
    noArgsCommandList().toLower.contains(c.toLower)

proc isToggleArgsCommand*(
  c: Runes,
  isCaseSensitive: bool = false): bool {.used.} =
    # NOTE: Remove the used pragma if you use this.

    if isCaseSensitive:
      toggleArgsCommandList().contains(c)
    else:
      toggleArgsCommandList().toLower.contains(c.toLower)

proc isNumberArgsCommand*(
  c: Runes,
  isCaseSensitive: bool = false): bool {.used.} =
    # NOTE: Remove the used pragma if you use this.

    if isCaseSensitive:
      numberArgsCommandList().contains(c)
    else:
      numberArgsCommandList().toLower.contains(c.toLower)

proc isTextArgsCommand*(
  c: Runes,
  isCaseSensitive: bool = false): bool {.used.} =
    # NOTE: Remove the used pragma if you use this.

    if isCaseSensitive:
      textArgsCommandList().contains(c)
    else:
      textArgsCommandList().toLower.contains(c.toLower)

proc isPathArgsCommand*(
  c: Runes,
  isCaseSensitive: bool = false): bool {.used.} =
    # NOTE: Remove the used pragma if you use this.

    if isCaseSensitive:
      pathArgsCommandList().contains(c)
    else:
      pathArgsCommandList().toLower.contains(c.toLower)

proc isThemeArgsCommand*(
  c: Runes,
  isCaseSensitive: bool = false): bool {.used.} =
    # NOTE: Remove the used pragma if you use this.

    if isCaseSensitive:
      themeArgsCommandList().contains(c)
    else:
      themeArgsCommandList().toLower.contains(c.toLower)

proc isForceWriteAndQuitCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "wq!") == 0

proc isForceWriteCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "w!") == 0

proc isPutConfigFileCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "putconfigfile") == 0

proc isDeleteTrailingSpacesCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and
         cmpIgnoreCase($command[0], "deletetrailingspaces") == 0

proc isOpenHelpCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "help") == 0

proc isOpenLogViweerCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "log") == 0

proc isOpenBufferManagerCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "buf") == 0

proc isChangeCursorLineCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "cursorline") == 0

proc isListAllBufferCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "ls") == 0

proc isWriteAndQuitAllBufferCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "wqa") == 0

proc isForceAllBufferQuitCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "qa!") == 0

proc isAllBufferQuitCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "qa") == 0

proc isVerticalSplitWindowCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "vs") == 0

proc isHorizontalSplitWindowCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "sv") == 0

proc isFilerIconSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "icon") == 0

proc isLiveReloadOfConfSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "livereload") == 0

proc isChangeThemeSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "theme") == 0

proc isTabLineSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "tab") == 0

proc isSyntaxSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "syntax") == 0

proc isTabStopSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and
  cmpIgnoreCase($command[0], "tabstop") == 0 and
  isDigit(command[1])

proc isAutoCloseParenSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "paren") == 0

proc isAutoIndentSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "indent") == 0

proc isIndentationLinesSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "indentationlines") == 0

proc isLineNumberSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "linenum") == 0

proc isStatusLineSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "statusline") == 0

proc isIncrementalSearchSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "incrementalsearch") == 0

proc isHighlightPairOfParenSettigCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "highlightparen") == 0

proc isAutoDeleteParenSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "deleteparen") == 0

proc isSmoothScrollSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "smoothscroll") == 0

proc isSmoothScrollMinDelaySettingCommand*(
  command: seq[Runes]): bool {.inline.} =
    command.len == 2 and
    cmpIgnoreCase($command[0], "scrollmindelay") == 0 and
    isDigit(command[1])

proc isSmoothScrollMaxDelaySettingCommand*(
  command: seq[Runes]): bool {.inline.} =
    command.len == 2 and
    cmpIgnoreCase($command[0], "scrollmaxdelay") == 0 and
    isDigit(command[1])

proc isHighlightCurrentWordSettingCommand*(
  command: seq[Runes]): bool {.inline.} =
    command.len == 2 and cmpIgnoreCase($command[0], "highlightcurrentword") == 0

proc isSystemClipboardSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "clipboard") == 0

proc isHighlightFullWidthSpaceSettingCommand*(
  command: seq[Runes]): bool {.inline.} =
    command.len == 2 and cmpIgnoreCase($command[0], "highlightfullspace") == 0

proc isMultipleStatusLineSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "multiplestatusline") == 0

proc isBuildOnSaveSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "buildonsave") == 0

proc isShowGitInInactiveSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "showgitinactive") == 0

proc isIgnorecaseSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "ignorecase") == 0

proc isSmartcaseSettingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "smartcase") == 0

proc isHighlightCurrentLineSettingCommand*(
  command: seq[Runes]): bool {.inline.} =

    command.len == 2 and
    cmpIgnoreCase($command[0], "highlightcurrentline") == 0

proc isTurnOffHighlightingCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "noh") == 0

proc isDeleteCurrentBufferStatusCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "bd") == 0

proc isDeleteBufferStatusCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and
  cmpIgnoreCase($command[0], "bd") == 0 and
  isDigit(command[1])

proc isChangeFirstBufferCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "bfirst") == 0

proc isChangeLastBufferCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "blast") == 0

proc isOpenBufferByNumberCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and
  cmpIgnoreCase($command[0], "b") == 0 and
  isDigit(command[1])

proc isChangeNextBufferCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "bnext") == 0

proc isChangePreveBufferCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "bprev") == 0

proc isJumpCommand*(command: seq[Runes]): bool =
  command.len == 1 and isDigit(command[0])

proc isJumpCommand*(bufStatus: BufferStatus, command: seq[Runes]): bool =
  isJumpCommand(command) and
  (bufStatus.prevMode == Mode.normal or
   bufStatus.prevMode == Mode.logviewer)

proc isEditCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "e") == 0

proc isOpenInHorizontalSplitWindowCommand*(command: seq[Runes]): bool =
  command.len in {1..2} and
  cmpIgnoreCase($command[0], "sp") == 0

proc isOpenInVerticalSplitWindowCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 2 and cmpIgnoreCase($command[0], "vs") == 0

proc isWriteCommand*(command: seq[Runes]): bool =
  command.len in {1, 2} and
  cmpIgnoreCase($command[0], "w") == 0

proc isWriteCommand*(bufStatus: BufferStatus, command: seq[Runes]): bool =
  command.len in {1, 2} and
  cmpIgnoreCase($command[0], "w") == 0 and
  (bufStatus.prevMode == Mode.normal or bufStatus.prevMode == Mode.config)

proc isQuitCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "q") == 0

proc isWriteAndQuitCommand*(command: seq[Runes]): bool =
  command.len == 1 and
  cmpIgnoreCase($command[0], "wq") == 0

proc isWriteAndQuitCommand*(bufStatus: BufferStatus, command: seq[Runes]): bool =
  command.len == 1 and
  cmpIgnoreCase($command[0], "wq") == 0 and
  bufStatus.prevMode == Mode.normal

proc isForceQuitCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "q!") == 0

proc isShellCommand*(command: seq[Runes]): bool {.inline.} =
  command.len >= 1 and command[0][0] == ru'!'

proc isBackgroundCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "bg") == 0

proc isManualCommand*(command: seq[Runes]): bool {.inline.} =
  # TODO:  Configure a default manual page to show on `:man`.
  command.len > 1 and cmpIgnoreCase($command[0], "man") == 0

proc isReplaceCommand*(command: seq[Runes]): bool {.inline.} =
  command.len >= 1 and
  command[0].len > 4 and
  command[0][0 .. 2] == ru"%s/"

proc isCreateNewEmptyBufferCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "ene") == 0

proc isNewEmptyBufferInSplitWindowHorizontallyCommand*(
  command: seq[Runes]): bool {.inline.} =

    command.len == 1 and cmpIgnoreCase($command[0], "new") == 0

proc isNewEmptyBufferInSplitWindowVerticallyCommand*(
  command: seq[Runes]): bool {.inline.} =

    command.len == 1 and cmpIgnoreCase($command[0], "vnew") == 0

proc isQuickRunCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "run") == 0

proc isRecentFileModeCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "recent") == 0

proc isBackupManagerCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "backup") == 0

proc isStartConfigModeCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "conf") == 0

proc isStartDebugModeCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "debug") == 0

proc isBuildCommand*(command: seq[Runes]): bool {.inline.} =
  command.len == 1 and cmpIgnoreCase($command[0], "build") == 0

proc isValidExCommand*(commandSplit: seq[Runes]): bool =
  ## Return true if valid ex command and valid args.

  if commandSplit.len == 0 or commandSplit[0].len == 0: return false

  return
    isJumpCommand(commandSplit) or
    isEditCommand(commandSplit) or
    isOpenInHorizontalSplitWindowCommand(commandSplit) or
    isOpenInVerticalSplitWindowCommand(commandSplit) or
    isWriteCommand(commandSplit) or
    isQuitCommand(commandSplit) or
    isWriteAndQuitCommand(commandSplit) or
    isForceQuitCommand(commandSplit) or
    isShellCommand(commandSplit) or
    isBackgroundCommand(commandSplit) or
    isManualCommand(commandSplit) or
    isReplaceCommand(commandSplit) or
    isChangeNextBufferCommand(commandSplit) or
    isChangePreveBufferCommand(commandSplit) or
    isOpenBufferByNumberCommand(commandSplit) or
    isChangeFirstBufferCommand(commandSplit) or
    isChangeLastBufferCommand(commandSplit) or
    isDeleteBufferStatusCommand(commandSplit) or
    isDeleteCurrentBufferStatusCommand(commandSplit) or
    isTurnOffHighlightingCommand(commandSplit) or
    isTabLineSettingCommand(commandSplit) or
    isStatusLineSettingCommand(commandSplit) or
    isLineNumberSettingCommand(commandSplit) or
    isIndentationLinesSettingCommand(commandSplit) or
    isAutoIndentSettingCommand(commandSplit) or
    isAutoCloseParenSettingCommand(commandSplit) or
    isTabStopSettingCommand(commandSplit) or
    isSyntaxSettingCommand(commandSplit) or
    isChangeThemeSettingCommand(commandSplit) or
    isChangeCursorLineCommand(commandSplit) or
    isVerticalSplitWindowCommand(commandSplit) or
    isHorizontalSplitWindowCommand(commandSplit) or
    isAllBufferQuitCommand(commandSplit) or
    isForceAllBufferQuitCommand(commandSplit) or
    isWriteAndQuitAllBufferCommand(commandSplit) or
    isListAllBufferCommand(commandSplit) or
    isOpenBufferManagerCommand(commandSplit) or
    isLiveReloadOfConfSettingCommand(commandSplit) or
    isIncrementalSearchSettingCommand(commandSplit) or
    isOpenLogViweerCommand(commandSplit) or
    isHighlightPairOfParenSettigCommand(commandSplit) or
    isAutoDeleteParenSettingCommand(commandSplit) or
    isSmoothScrollSettingCommand(commandSplit) or
    isSmoothScrollMinDelaySettingCommand(commandSplit) or
    isSmoothScrollMaxDelaySettingCommand(commandSplit) or
    isHighlightCurrentWordSettingCommand(commandSplit) or
    isSystemClipboardSettingCommand(commandSplit) or
    isHighlightFullWidthSpaceSettingCommand(commandSplit) or
    isMultipleStatusLineSettingCommand(commandSplit) or
    isBuildOnSaveSettingCommand(commandSplit) or
    isOpenHelpCommand(commandSplit) or
    isCreateNewEmptyBufferCommand(commandSplit) or
    isNewEmptyBufferInSplitWindowHorizontallyCommand(commandSplit) or
    isNewEmptyBufferInSplitWindowVerticallyCommand(commandSplit) or
    isFilerIconSettingCommand(commandSplit) or
    isDeleteTrailingSpacesCommand(commandSplit) or
    isPutConfigFileCommand(commandSplit) or
    isShowGitInInactiveSettingCommand(commandSplit) or
    isQuickRunCommand(commandSplit) or
    isRecentFileModeCommand(commandSplit) or
    isBackupManagerCommand(commandSplit) or
    isStartConfigModeCommand(commandSplit) or
    isIgnorecaseSettingCommand(commandSplit) or
    isSmartcaseSettingCommand(commandSplit) or
    isForceWriteCommand(commandSplit) or
    isForceWriteAndQuitCommand(commandSplit) or
    isStartDebugModeCommand(commandSplit) or
    isHighlightCurrentLineSettingCommand(commandSplit) or
    isBuildCommand(commandSplit)

proc getArgsType*(command: Runes): Result[ArgsType, string] =
  ## Return ArgsType if valid ex command.

  let lowerCommand = command.toLower
  for line in ExCommandInfoList:
    if line.command.toLowerAscii.toRunes == lowerCommand:
      return Result[ArgsType, string].ok line.argsType

  return Result[ArgsType, string].err "Invalid command"

proc getDescription*(command: Runes): Result[Runes, string] =
  ## Return th command description if valid ex command.

  let lowerCommand = command.toLower
  for line in ExCommandInfoList:
    if line.command.toLowerAscii.toRunes == lowerCommand:
      return Result[Runes, string].ok line.description.toRunes

  return Result[Runes, string].err "Invalid command"

