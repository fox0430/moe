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

import std/[unittest]
import pkg/results
import moepkg/unicodeext

import moepkg/exmodeutils {.all.}

suite "exmodeutils: splitExCommandBuffer":
  test "Without quotes":
    check splitExCommandBuffer(ru"arg1 arg2 arg3") ==
      @["arg1", "arg2", "arg3"].toSeqRunes

  test "Basic single quotes":
    check splitExCommandBuffer(ru"arg1 'arg2-1 args2-2' arg3") ==
      @["arg1", "arg2-1 args2-2", "arg3"].toSeqRunes

  test "Backslash with single quotes":
    check splitExCommandBuffer(ru"arg1 'arg2-1\' args2-2' arg3") ==
      @["arg1", "arg2-1' args2-2", "arg3"].toSeqRunes

  test "Basic double quotes":
    check splitExCommandBuffer(ru"""arg1 "arg2-1 args2-2" arg3""") ==
      @["arg1", "arg2-1 args2-2", "arg3"].toSeqRunes

  test "Backslash with double quotes":
    check splitExCommandBuffer(ru"""arg1 "arg2-1\" args2-2" arg3""") ==
      @["arg1", "arg2-1\" args2-2", "arg3"].toSeqRunes

  test "Double quotes in single quotes":
    check splitExCommandBuffer(ru"""arg1 'arg2-1 "args2-2"' arg3""") ==
      @["arg1", "arg2-1 \"args2-2\"", "arg3"].toSeqRunes

  test "Single quotes in in double quotes":
    check splitExCommandBuffer(ru"""arg1 "arg2-1 'args2-2'" arg3""") ==
      @["arg1", "arg2-1 'args2-2'", "arg3"].toSeqRunes

suite "exmodeutils: isExCommand":
  test "Case insensitive":
    for c in exCommandList(): check isExCommand(c)
    for c in lowerExCommandList(): check isExCommand(c)

  test "Case sensitive":
    const IsCaseSensitive = true
    for c in exCommandList(): check isExCommand(c, IsCaseSensitive)
    for c in lowerExCommandList():
      if not exCommandList().contains(c):
        check not isExCommand(c.toLower, IsCaseSensitive)

suite "exmodeutils: isToggleArgsCommand":
  test "Case insensitive":
    for c in noArgsCommandList(): check isNoArgsCommand(c)
    for c in noArgsCommandList(): check isNoArgsCommand(c.toLower)

  test "Case sensitive":
    const IsCaseSensitive = true
    for c in noArgsCommandList(): check isNoArgsCommand(c, IsCaseSensitive)
    for c in noArgsCommandList():
      if not exCommandList().contains(c):
        check isNoArgsCommand(c.toLower, IsCaseSensitive)

suite "exmodeutils: isToggleArgsCommand":
  test "Case insensitive":
    for c in toggleArgsCommandList(): check isToggleArgsCommand(c)
    for c in toggleArgsCommandList(): check isToggleArgsCommand(c.toLower)

  test "Case sensitive":
    const IsCaseSensitive = true
    for c in toggleArgsCommandList(): check isToggleArgsCommand(c, IsCaseSensitive)
    for c in toggleArgsCommandList():
      if not exCommandList().contains(c.toLower):
        check not isToggleArgsCommand(c.toLower, IsCaseSensitive)

suite "exmodeutils: isNumberArgsCommand":
  test "Case insensitive":
    for c in numberArgsCommandList(): check isNumberArgsCommand(c)
    for c in numberArgsCommandList(): check isNumberArgsCommand(c.toLower)

  test "Case sensitive":
    const IsCaseSensitive = true
    for c in numberArgsCommandList(): check isNumberArgsCommand(c, IsCaseSensitive)
    for c in numberArgsCommandList():
      if not exCommandList().contains(c.toLower):
        check not isNumberArgsCommand(c.toLower, IsCaseSensitive)

suite "exmodeutils: isTextArgsCommand":
  test "Case insensitive":
    for c in textArgsCommandList(): check isTextArgsCommand(c)
    for c in textArgsCommandList(): check isTextArgsCommand(c.toLower)

  test "Case sensitive":
    const IsCaseSensitive = true
    for c in textArgsCommandList(): check isTextArgsCommand(c, IsCaseSensitive)
    for c in textArgsCommandList():
      if not exCommandList().contains(c.toLower):
        check not isTextArgsCommand(c.toLower, IsCaseSensitive)

suite "exmodeutils: isPathArgsCommand":
  test "Case insensitive":
    for c in pathArgsCommandList(): check isPathArgsCommand(c)
    for c in pathArgsCommandList(): check isPathArgsCommand(c.toLower)

  test "Case sensitive":
    const IsCaseSensitive = true
    for c in pathArgsCommandList(): check isPathArgsCommand(c, IsCaseSensitive)
    for c in pathArgsCommandList():
      if not exCommandList().contains(c.toLower):
        check not isPathArgsCommand(c.toLower, IsCaseSensitive)

suite "exmodeutils: isThemeArgsCommand":
  test "Case insensitive":
    for c in themeArgsCommandList(): check isThemeArgsCommand(c)
    for c in themeArgsCommandList(): check isThemeArgsCommand(c.toLower)

  test "Case sensitive":
    const IsCaseSensitive = true
    for c in themeArgsCommandList(): check isThemeArgsCommand(c, IsCaseSensitive)
    for c in themeArgsCommandList():
      if not exCommandList().contains(c.toLower):
        check not isThemeArgsCommand(c.toLower, IsCaseSensitive)

suite "exmodeutils: isForceWriteAndQuitCommand":
  test "Valid":
    check isForceWriteAndQuitCommand(@["wq!"].toSeqRunes)

  test "Invalid":
    check not isForceWriteAndQuitCommand(@["a"].toSeqRunes)

suite "exmodeutils: isForceWriteCommand":
  test "Valid":
    check isForceWriteCommand(@["w!"].toSeqRunes)

  test "Invalid":
    check not isForceWriteCommand(@["a"].toSeqRunes)

suite "exmodeutils: isPutConfigFileCommand":
  test "Valid":
    check isPutConfigFileCommand(@["putConfigFile"].toSeqRunes)

  test "Invalid":
    check not isPutConfigFileCommand(@["a"].toSeqRunes)

suite "exmodeutils: isDeleteTrailingSpacesCommand":
  test "Valid":
    check isDeleteTrailingSpacesCommand(@["deleteTrailingSpaces"].toSeqRunes)

  test "Invalid":
    check not isDeleteTrailingSpacesCommand(@["a"].toSeqRunes)

suite "exmodeutils: isOpenHelpCommand":
  test "Valid":
    check isOpenHelpCommand(@["help"].toSeqRunes)

  test "Invalid":
    check not isOpenHelpCommand(@["a"].toSeqRunes)

suite "exmodeutils: isOpenLogViweerCommand":
  test "Valid":
    check isOpenLogViweerCommand(@["log"].toSeqRunes)

  test "Invalid":
    check not isOpenLogViweerCommand(@["a"].toSeqRunes)

suite "exmodeutils: isOpenBufferManagerCommand":
  test "Valid":
    check isOpenBufferManagerCommand(@["buf"].toSeqRunes)

  test "Invalid":
    check not isOpenBufferManagerCommand(@["a"].toSeqRunes)

suite "exmodeutils: isChangeCursorLineCommand":
  test "Valid":
    check isChangeCursorLineCommand(@["cursorLine", "on"].toSeqRunes)

  test "Invalid":
    check not isChangeCursorLineCommand(@["a"].toSeqRunes)

suite "exmodeutils: isListAllBufferCommand":
  test "Valid":
    check isListAllBufferCommand(@["ls"].toSeqRunes)

  test "Invalid":
    check not isListAllBufferCommand(@["a"].toSeqRunes)

suite "exmodeutils: isWriteAndQuitAllBufferCommand":
  test "Valid":
    check isWriteAndQuitAllBufferCommand(@["wqa"].toSeqRunes)

  test "Invalid":
    check not isWriteAndQuitAllBufferCommand(@["a"].toSeqRunes)

suite "exmodeutils: isForceAllBufferQuitCommand":
  test "Valid":
    check isForceAllBufferQuitCommand(@["qa!"].toSeqRunes)

  test "Invalid":
    check not isForceAllBufferQuitCommand(@["a"].toSeqRunes)

suite "exmodeutils: isAllBufferQuitCommand":
  test "Valid":
    check isAllBufferQuitCommand(@["qa"].toSeqRunes)

  test "Invalid":
    check not isAllBufferQuitCommand(@["a"].toSeqRunes)

suite "exmodeutils: isVerticalSplitWindowCommand":
  test "Valid":
    check isVerticalSplitWindowCommand(@["vs"].toSeqRunes)

  test "Invalid":
    check not isVerticalSplitWindowCommand(@["a"].toSeqRunes)

suite "exmodeutils: isHorizontalSplitWindowCommand":
  test "Valid":
    check isHorizontalSplitWindowCommand(@["sv"].toSeqRunes)

  test "Invalid":
    check not isHorizontalSplitWindowCommand(@["a"].toSeqRunes)

suite "exmodeutils: isFilerIconSettingCommand":
  test "Valid":
    check isFilerIconSettingCommand(@["icon", "on"].toSeqRunes)

  test "Invalid":
    check not isFilerIconSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isLiveReloadOfConfSettingCommand":
  test "Valid":
    check isLiveReloadOfConfSettingCommand(@["liveReload", "on"].toSeqRunes)

  test "Invalid":
    check not isLiveReloadOfConfSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isChangeThemeSettingCommand":
  test "Valid":
    check isChangeThemeSettingCommand(@["theme", "dark"].toSeqRunes)

  test "Invalid":
    check not isChangeThemeSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isTabLineSettingCommand":
  test "Valid":
    check isTabLineSettingCommand(@["tab", "on"].toSeqRunes)

  test "Invalid":
    check not isTabLineSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isSyntaxSettingCommand":
  test "Valid":
    check isSyntaxSettingCommand(@["syntax", "on"].toSeqRunes)

  test "Invalid":
    check not isSyntaxSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isTabStopSettingCommand":
  test "Valid":
    check isTabStopSettingCommand(@["tabstop", "2"].toSeqRunes)

  test "Invalid":
    check not isTabStopSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isAutoCloseParenSettingCommand":
  test "Valid":
    check isAutoCloseParenSettingCommand(@["paren", "on"].toSeqRunes)

  test "Invalid":
    check not isAutoCloseParenSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isAutoIndentSettingCommand":
  test "Valid":
    check isAutoIndentSettingCommand(@["indent", "on"].toSeqRunes)

  test "Invalid":
    check not isAutoIndentSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isIndentationLinesSettingCommand":
  test "Valid":
    check isIndentationLinesSettingCommand(
      @["indentationLines", "on"].toSeqRunes)

  test "Invalid":
    check not isIndentationLinesSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isLineNumberSettingCommand":
  test "Valid":
    check isLineNumberSettingCommand(@["lineNum", "on"].toSeqRunes)

  test "Invalid":
    check not isLineNumberSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isStatusLineSettingCommand":
  test "Valid":
    check isStatusLineSettingCommand(@["statusLine", "on"].toSeqRunes)

  test "Invalid":
    check not isStatusLineSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isIncrementalSearchSettingCommand":
  test "Valid":
    check isIncrementalSearchSettingCommand(
      @["incrementalSearch", "on"].toSeqRunes)

  test "Invalid":
    check not isIncrementalSearchSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isHighlightPairOfParenSettigCommand":
  test "Valid":
    check isHighlightPairOfParenSettigCommand(
      @["highlightParen", "on"].toSeqRunes)

  test "Invalid":
    check not isHighlightPairOfParenSettigCommand(@["a"].toSeqRunes)

suite "exmodeutils: isAutoDeleteParenSettingCommand":
  test "Valid":
    check isAutoDeleteParenSettingCommand(@["deleteParen", "on"].toSeqRunes)

  test "Invalid":
    check not isAutoDeleteParenSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isSmoothScrollSettingCommand":
  test "Valid":
    check isSmoothScrollSettingCommand(@["smoothScroll", "on"].toSeqRunes)

  test "Invalid":
    check not isSmoothScrollSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isSmoothScrollMinDelaySettingCommand":
  test "Valid":
    check isSmoothScrollMinDelaySettingCommand(@["scrollMinDelay", "1"].toSeqRunes)

  test "Invalid":
    check not isSmoothScrollMinDelaySettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isSmoothScrollMaxDelaySettingCommand":
  test "Valid":
    check isSmoothScrollMaxDelaySettingCommand(@["scrollMaxDelay", "1"].toSeqRunes)

  test "Invalid":
    check not isSmoothScrollMaxDelaySettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isHighlightCurrentWordSettingCommand":
  test "Valid":
    check isHighlightCurrentWordSettingCommand(
      @["highlightCurrentWord", "on"].toSeqRunes)

  test "Invalid":
    check not isHighlightCurrentWordSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isSystemClipboardSettingCommand":
  test "Valid":
    check isSystemClipboardSettingCommand(@["clipboard", "on"].toSeqRunes)

  test "Invalid":
    check not isSystemClipboardSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isHighlightFullWidthSpaceSettingCommand":
  test "Valid":
    check isHighlightFullWidthSpaceSettingCommand(
      @["highlightFullSpace", "on"].toSeqRunes)

  test "Invalid":
    check not isHighlightFullWidthSpaceSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isMultipleStatusLineSettingCommand":
  test "Valid":
    check isMultipleStatusLineSettingCommand(
      @["multipleStatusLine", "on"].toSeqRunes)

  test "Invalid":
    check not isMultipleStatusLineSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isBuildOnSaveSettingCommand":
  test "Valid":
    check isBuildOnSaveSettingCommand(
      @["buildOnSave", "on"].toSeqRunes)

  test "Invalid":
    check not isBuildOnSaveSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isShowGitInInactiveSettingCommand":
  test "Valid":
    check isShowGitInInactiveSettingCommand(
      @["showGitInactive", "on"].toSeqRunes)

  test "Invalid":
    check not isShowGitInInactiveSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isIgnorecaseSettingCommand":
  test "Valid":
    check isIgnorecaseSettingCommand(@["ignorecase", "on"].toSeqRunes)

  test "Invalid":
    check not isIgnorecaseSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isSmartcaseSettingCommand":
  test "Valid":
    check isSmartcaseSettingCommand(@["smartcase", "on"].toSeqRunes)

  test "Invalid":
    check not isSmartcaseSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isHighlightCurrentLineSettingCommand":
  test "Valid":
    check isHighlightCurrentLineSettingCommand(
      @["highlightCurrentLine", "on"].toSeqRunes)

  test "Invalid":
    check not isHighlightCurrentLineSettingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isTurnOffHighlightingCommand":
  test "Valid":
    check isTurnOffHighlightingCommand(@["noh"].toSeqRunes)

  test "Invalid":
    check not isTurnOffHighlightingCommand(@["a"].toSeqRunes)

suite "exmodeutils: isDeleteCurrentBufferStatusCommand":
  test "Valid":
    check isDeleteCurrentBufferStatusCommand(@["bd"].toSeqRunes)

  test "Invalid":
    check not isDeleteCurrentBufferStatusCommand(@["a"].toSeqRunes)

suite "exmodeutils: isDeleteBufferStatusCommand":
  test "Valid":
    check isDeleteBufferStatusCommand(@["bd", "1"].toSeqRunes)

  test "Invalid":
    check not isDeleteBufferStatusCommand(@["a"].toSeqRunes)

suite "exmodeutils: isChangeFirstBufferCommand":
  test "Valid":
    check isChangeFirstBufferCommand(@["bfirst"].toSeqRunes)

  test "Invalid":
    check not isChangeFirstBufferCommand(@["a"].toSeqRunes)

suite "exmodeutils: isChangeLastBufferCommand":
  test "Valid":
    check isChangeLastBufferCommand(@["blast"].toSeqRunes)

  test "Invalid":
    check not isChangeLastBufferCommand(@["a"].toSeqRunes)

suite "exmodeutils: isOpenBufferByNumberCommand":
  test "Valid":
    check isOpenBufferByNumberCommand(@["b", "1"].toSeqRunes)

  test "Invalid":
    check not isOpenBufferByNumberCommand(@["a"].toSeqRunes)

suite "exmodeutils: isChangeNextBufferCommand":
  test "Valid":
    check isChangeNextBufferCommand(@["bnext"].toSeqRunes)

  test "Invalid":
    check not isChangeNextBufferCommand(@["a"].toSeqRunes)

suite "exmodeutils: isChangePreveBufferCommand":
  test "Valid":
    check isChangePreveBufferCommand(@["bprev"].toSeqRunes)

  test "Invalid":
    check not isChangePreveBufferCommand(@["a"].toSeqRunes)

suite "exmodeutils: isJumpCommand":
  test "Valid":
    check isJumpCommand(@["1"].toSeqRunes)

  test "Invalid":
    check not isJumpCommand(@["a"].toSeqRunes)

suite "exmodeutils: isEditCommand":
  test "Valid":
    check isEditCommand(@["e", "arg"].toSeqRunes)

  test "Invalid":
    check not isEditCommand(@["a"].toSeqRunes)

suite "exmodeutils: isOpenInHorizontalSplitWindowCommand":
  test "Valid":
    check isOpenInHorizontalSplitWindowCommand(@["sp"].toSeqRunes)

  test "Valid 2":
    check isOpenInHorizontalSplitWindowCommand(@["sp", "arg"].toSeqRunes)

  test "Invalid":
    check not isOpenInHorizontalSplitWindowCommand(@["a"].toSeqRunes)

suite "exmodeutils: isOpenInVerticalSplitWindowCommand":
  test "Valid":
    check isOpenInVerticalSplitWindowCommand(@["vs", "arg"].toSeqRunes)

  test "Invalid":
    check not isOpenInVerticalSplitWindowCommand(@["a"].toSeqRunes)

suite "exmodeutils: isWriteCommand":
  test "Valid":
    check isWriteCommand(@["w"].toSeqRunes)

  test "Invalid":
    check not isWriteCommand(@["a"].toSeqRunes)

suite "exmodeutils: isQuitCommand":
  test "Valid":
    check isQuitCommand(@["q"].toSeqRunes)

  test "Invalid":
    check not isQuitCommand(@["a"].toSeqRunes)

suite "exmodeutils: isWriteAndQuitCommand":
  test "Valid":
    check isWriteAndQuitCommand(@["wq"].toSeqRunes)

  test "Invalid":
    check not isWriteAndQuitCommand(@["a"].toSeqRunes)

suite "exmodeutils: isForceQuitCommand":
  test "Valid":
    check isForceQuitCommand(@["q!"].toSeqRunes)

  test "Invalid":
    check not isForceQuitCommand(@["a"].toSeqRunes)

suite "exmodeutils: isShellCommand":
  test "Valid":
    check isShellCommand(@["!", "arg"].toSeqRunes)

  test "Valid 2":
    check isShellCommand(@["!", "arg1", "arg2"].toSeqRunes)

  test "Invalid":
    check not isShellCommand(@["a"].toSeqRunes)

suite "exmodeutils: isBackgroundCommand":
  test "Valid":
    check isBackgroundCommand(@["bg"].toSeqRunes)

  test "Invalid":
    check not isBackgroundCommand(@["a"].toSeqRunes)

suite "exmodeutils: isManualCommand":
  test "Valid":
    check isManualCommand(@["man", "arg"].toSeqRunes)

  test "Invalid":
    check not isManualCommand(@["a"].toSeqRunes)

suite "exmodeutils: isReplaceCommand":
  test "Valid":
    check isReplaceCommand(@["%s/arg1/arg2/"].toSeqRunes)

  test "Invalid":
    check not isReplaceCommand(@["a"].toSeqRunes)

suite "exmodeutils: isCreateNewEmptyBufferCommand":
  test "Valid":
    check isCreateNewEmptyBufferCommand(@["ene"].toSeqRunes)

  test "Invalid":
    check not isCreateNewEmptyBufferCommand(@["a"].toSeqRunes)

suite "exmodeutils: isNewEmptyBufferInSplitWindowHorizontallyCommand":
  test "Valid":
    check isNewEmptyBufferInSplitWindowHorizontallyCommand(@["new"].toSeqRunes)

  test "Invalid":
    check not isNewEmptyBufferInSplitWindowHorizontallyCommand(
      @["a"].toSeqRunes)

suite "exmodeutils: isNewEmptyBufferInSplitWindowVerticallyCommand":
  test "Valid":
    check isNewEmptyBufferInSplitWindowVerticallyCommand(@["vnew"].toSeqRunes)

  test "Invalid":
    check not isNewEmptyBufferInSplitWindowVerticallyCommand(@["a"].toSeqRunes)

suite "exmodeutils: isQuickRunCommand":
  test "Valid":
    check isQuickRunCommand(@["run"].toSeqRunes)

  test "Invalid":
    check not isQuickRunCommand(@["a"].toSeqRunes)

suite "exmodeutils: isRecentFileModeCommand":
  test "Valid":
    check isRecentFileModeCommand(@["recent"].toSeqRunes)

  test "Invalid":
    check not isRecentFileModeCommand(@["a"].toSeqRunes)

suite "exmodeutils: isBackupManagerCommand":
  test "Valid":
    check isBackupManagerCommand(@["backup"].toSeqRunes)
  test "Invalid":
    check not isBackupManagerCommand(@["a"].toSeqRunes)

suite "exmodeutils: isStartConfigModeCommand":
  test "Valid":
    check isStartConfigModeCommand(@["conf"].toSeqRunes)
  test "Invalid":
    check not isStartConfigModeCommand(@["a"].toSeqRunes)

suite "exmodeutils: isStartDebugModeCommand":
  test "Valid":
    check isStartDebugModeCommand(@["debug"].toSeqRunes)
  test "Invalid":
    check not isStartDebugModeCommand(@["a"].toSeqRunes)

suite "exmodeutils: isBuildCommand":
  test "Valid":
    check isBuildCommand(@["build"].toSeqRunes)
  test "Invalid":
    check not isBuildCommand(@["a"].toSeqRunes)

suite "exmodeutils: isValidExCommand":
  test "Valid":
    check isValidExCommand(@["w"].toSeqRunes)

  test "Valid 2":
    check isValidExCommand(@["e", "path"].toSeqRunes)

  test "Invalid":
    check not isValidExCommand(@[].toSeqRunes)
    check not isValidExCommand(@[""].toSeqRunes)

  test "Invalid 2":
    check not isValidExCommand(@["a"].toSeqRunes)

  test "Invalid 3":
    check not isValidExCommand(@["e"].toSeqRunes)

suite "exmodeutils: getArgsType":
  test "Valid":
    check getArgsType(ru"e").get == ArgsType.path

  test "Invalid":
    check getArgsType(ru"a").isErr

suite "exmodeutils: getDescription":
  test "Valid":
    check getDescription(ru"e").isOk

  test "Invalid":
    check getDescription(ru"a").isErr

suite "exmodeutils: isValidFileOpenCommand":
  test "Valid 1":
    check isValidFileOpenCommand(ru"e moe.nimble")

  test "Valid 2":
    check isValidFileOpenCommand(ru"e src/moe.nim")

  test "Valid 3":
    check isValidFileOpenCommand(ru"e ./src/moepkg/autocomplete.nim")

  test "Valid 4":
    check isValidFileOpenCommand(ru"vs moe.nimble")

  test "Valid 5":
    check isValidFileOpenCommand(ru"sv moe.nimble")

  test "Valid 6":
    check isValidFileOpenCommand(ru"sp moe.nimble")

  test "Invalid 1":
    check not isValidFileOpenCommand(ru"")

  test "Invalid 2":
    check not isValidFileOpenCommand(ru"e xyz")

  test "Invalid 3":
    check not isValidFileOpenCommand(ru"! moe.nimble")

  test "Invalid 4":
    check not isValidFileOpenCommand(ru"! src")

  test "Invalid 5":
    check not isValidFileOpenCommand(ru"moe.nimble")
