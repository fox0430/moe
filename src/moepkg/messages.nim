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

import std/[strformat, os, strutils]

import color, unicodeext, settings, commandline, independentutils, messagelog

proc writeMessageOnCommandLine*(
    commandLine: CommandLine,
    message: string,
    color: EditorColorPairIndex,
    log = true,
    screen = true,
) =
  if log or screen:
    let m = message.toRunes
    if log:
      addMessageLog m
    if screen:
      commandLine.write(m)
      commandLine.setColor(color)

proc writeMessageOnCommandLine*(
    commandLine: CommandLine, message: string, log = false, screen = true
) {.inline.} =
  commandLine.writeMessageOnCommandLine(
    message, EditorColorPairIndex.commandLine, log, screen
  )

proc writeStandard*(
    c: CommandLine, message: string, log = true, screen = true
) {.inline.} =
  c.writeMessageOnCommandLine(message, EditorColorPairIndex.commandLine, log, screen)

proc writeInfo*(c: CommandLine, message: string, log = true, screen = true) {.inline.} =
  c.writeMessageOnCommandLine(fmt"Info: {message}", EditorColorPairIndex.commandLine)

proc writeLog*(c: CommandLine, message: string, log = true, screen = true) {.inline.} =
  c.writeMessageOnCommandLine(fmt"Log: {message}", EditorColorPairIndex.commandLine)

proc writeDebug*(
    c: CommandLine, message: string, log = true, screen = true
) {.inline.} =
  c.writeMessageOnCommandLine(fmt"Debug: {message}", EditorColorPairIndex.commandLine)

proc writeError*(c: CommandLine, message: string) {.inline.} =
  c.writeMessageOnCommandLine(
    fmt"Error: {message}", EditorColorPairIndex.errorMessage, true, true
  )

proc writeWarn*(c: CommandLine, message: string) {.inline.} =
  c.writeMessageOnCommandLine(fmt"Warn: {message}", EditorColorPairIndex.warnMessage)

proc writeNcursesColorError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Ncurses: Cannot use extened colors")

proc writeNoWriteError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("No write since last change")

proc writeSaveError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Failed to save the file")

proc writeRemoveFileError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Can not remove file")

proc writeRemoveDirError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Can not remove directory")

proc writeCopyFileError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Can not copy file")

proc writeFileOpenError*(commandLine: CommandLine, fileName: string) {.inline.} =
  commandLine.writeError(fmt"Can not open: {fileName}")

proc writeCreateDirError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Can not create directory")

proc writeMessageDeletedFile*(
    commandLine: CommandLine, filename: string, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.filerLogNotify
    isScreen = settings.screenNotifications and settings.filerScreenNotify

  if isLog or isScreen:
    let msg = "Deleted: " & filename
    commandLine.writeStandard(msg, log = isLog, screen = isScreen)

proc writeNoFileNameError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("No file name")

proc writeMessageYankedLine*(
    commandLine: CommandLine, numOfLine: int, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.yankLogNotify
    isScreen = settings.screenNotifications and settings.yankScreenNotify

  if isLog or isScreen:
    commandLine.writeStandard(
      fmt"{numOfLine} line(s) yanked", log = isLog, screen = isScreen
    )

proc writeMessageYankedCharacter*(
    commandLine: CommandLine, numOfChar: int, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.yankLogNotify
    isScreen = settings.screenNotifications and settings.yankScreenNotify

  if isLog or isScreen:
    commandLine.writeStandard(
      fmt"{numOfChar} character(s) yanked", log = isLog, screen = isScreen
    )

proc writeMessageAutoSave*(
    commandLine: CommandLine, filename: Runes, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.autoSaveLogNotify
    isScreen = settings.screenNotifications and settings.autoSaveScreenNotify

  if isLog or isScreen:
    commandLine.writeMessageOnCommandLine(fmt"Auto saved {filename}")

proc writeMessageSuccessBuildOnSave*(
    commandLine: CommandLine, path: Runes, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.buildOnSaveLogNotify
    isScreen = settings.screenNotifications and settings.buildOnSaveScreenNotify

  if isLog or isScreen:
    commandLine.writeStandard(
      fmt"Build on save successful: {path}", log = isLog, screen = isScreen
    )

proc writeMessageFailedBuildOnSaveError*(
    commandLine: CommandLine, path: Runes
) {.inline.} =
  commandLine.writeError(fmt"Build failed: {path}")

proc writeNotEditorCommandError*(commandLine: CommandLine, command: Runes) {.inline.} =
  commandLine.writeError(fmt"Not an editor command: {command}")

proc writeNotEditorCommandError*(
    commandLine: CommandLine, command: seq[Runes]
) {.inline.} =
  commandLine.writeNotEditorCommandError(command.join(ru" "))

proc writeMessageSaveFile*(
    commandLine: CommandLine, filename: Runes, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.saveLogNotify
    isScreen = settings.screenNotifications and settings.saveScreenNotify

  if isLog or isScreen:
    commandLine.writeStandard(fmt"Saved {filename}", log = isLog, screen = isScreen)

proc writeMessageSaveFileAndStartBuild*(
    commandLine: CommandLine, filename: Runes, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.buildOnSaveLogNotify
    isScreen = settings.screenNotifications and settings.buildOnSaveScreenNotify

  if isLog or isScreen:
    commandLine.writeStandard(
      fmt"Saved {filename} and start build...", log = isLog, screen = isScreen
    )

proc writeNoBufferDeletedError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("No buffers were deleted")

proc writePutConfigFile*(
    commandLine: CommandLine, configPath: string, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications
    isScreen = settings.screenNotifications

  if isLog or isScreen:
    commandLine.writeStandard(
      fmt"Wrote the current editor settings to {configPath}", isLog, isScreen
    )

proc writePutConfigFileError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Failed to put configuration file")

proc writePutConfigFileAlreadyExistError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Configuration file already exists")

proc writeOpenRecentlyUsedXbelError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError(getHomeDir() / ".local/share/recently-used.xbel not found")

proc writeFileNotFoundError*(commandLine: CommandLine, filename: Runes) {.inline.} =
  commandLine.writeError(fmt"{filename} not found")

proc writeStartAutoBackupMessage*(
    commandLine: CommandLine, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.autoBackupLogNotify
    isScreen = settings.screenNotifications and settings.autoBackupScreenNotify

  if isLog or isScreen:
    commandLine.writeMessageOnCommandLine("Start automatic backup...")

proc writeAutoBackupSuccessMessage*(
    commandLine: CommandLine, filePath: Runes, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.autoBackupLogNotify
    isScreen = settings.screenNotifications and settings.autoBackupScreenNotify

  if isLog or isScreen:
    commandLine.writeStandard(
      fmt"Automatic backup successful: {filePath}", log = isLog, screen = isScreen
    )

proc writeRunQuickRunMessage*(
    commandLine: CommandLine, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.quickRunLogNotify
    isScreen = settings.screenNotifications and settings.quickRunScreenNotify

  if isLog or isScreen:
    commandLine.writeStandard("Quick run...", log = isLog, screen = isScreen)

proc writeInRecordingOperations*(
    commandLine: CommandLine, registerName: Rune
) {.inline.} =
  commandLine.writeMessageOnCommandLine(fmt"recording @{registerName}")

proc writeAutoBackupFailedError*(commandLine: CommandLine, filename: Runes) {.inline.} =
  commandLine.writeError(fmt"Automatic backups failed: {filename}")

proc writeRunQuickRunTimeoutError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Quick run timeout")

proc writeRunQuickRunFailedError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Quick run failed")

proc writeInvalidItemInConfigurationFileError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeError(
    fmt"Failed to load configuration file: Invalid item: {message}"
  )

proc writeFailedToLoadConfigurationFileError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeError(fmt"Failed to load configuration file: {message}")

proc writeBackupRestoreError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Restore failed")

proc writeRestoreFileSuccessMessage*(
    commandLine: CommandLine, filename: Runes, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.restoreLogNotify
    isScreen = settings.screenNotifications and settings.restoreScreenNotify

  if isLog or isScreen:
    let msg = fmt"Restore successful {filename}"
    commandLine.writeMessageOnCommandLine(msg)

proc writeDeleteBackupError*(commandLine: CommandLine) {.inline.} =
  commandLine.writeError("Delete backup file failed")

proc writeExitHelp*(commandLine: CommandLine, settings: NotificationSettings) =
  let
    isLog = settings.logNotifications
    isScreen = settings.screenNotifications

  if isLog or isScreen:
    commandLine.writeStandard(
      "Type :qa and press <Enter> to exit moe", log = isLog, screen = isScreen
    )

proc writeCurrentCharInfo*(
    commandLine: CommandLine, r: Rune, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications
    isScreen = settings.screenNotifications

  if isLog or isScreen:
    let
      e = encodeUTF8(r)
      eHex = e[0].uint64.toHex
      eOct = int64(e[0]).toOct(5)
      msg = fmt "<{$r}>  {e[0]}  Hex {normalizeHex($eHex)}  Oct {$eOct}"
    commandLine.writeStandard(msg, log = isLog, screen = isScreen)

proc writeReadonlyModeWarning*(commandLine: CommandLine) {.inline.} =
  const msg = "Readonly mode"
  commandLine.writeWarn(msg)

proc writeManualCommandError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeError(fmt"No manual entry for {message}")

proc writeSyntaxCheckError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeError(fmt"Syntax check failed: {message}")

proc writeGitInfoUpdateError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeError(fmt"Update Git info: {message}")

proc writeBufferChangedWarn*(commandLine: CommandLine, filename: Runes) {.inline.} =
  commandLine.writeWarn(
    fmt"File {filename} has changed and the buffer was changed in Moe as well."
  )

proc writeDiffViewerError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeError(fmt"diff: {message}")

proc writeChangeThemeError*(commandLine: CommandLine, message: string) =
  commandLine.writeError(fmt"Error: Change theme failed: ${message}")

proc writePasteIgnoreWarn*(commandLine: CommandLine) {.inline.} =
  commandLine.writeWarn("Paste is ignored in this mode")

proc writeLspStandard*(
    commandLine: CommandLine, message: string, log = true, screen = true
) {.inline.} =
  commandLine.writeStandard(fmt"lsp: {message}", log, screen)

proc writeLspDebug*(
    commandLine: CommandLine, message: string, log = true, screen = true
) {.inline.} =
  commandLine.writeDebug(fmt"lsp: {message}", log, screen)

proc writeLspLog*(
    commandLine: CommandLine, message: string, log = true, screen = true
) {.inline.} =
  commandLine.writeLog(fmt"lsp: {message}", log, screen)

proc writeLspInfo*(
    commandLine: CommandLine, message: string, log = true, screen = true
) {.inline.} =
  commandLine.writeInfo(fmt"lsp: {message}", log, screen)

proc writeLspWarn*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeWarn(fmt"lsp: {message}")

proc writeLspError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeError(fmt"lsp: {message}")

proc writeLspServerStart*(
    commandLine: CommandLine, command: Runes, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.lspLogNotify
    isScreen = settings.screenNotifications and settings.lspScreenNotify

  if isLog or isScreen:
    commandLine.writeLspStandard(fmt"Server starting: {command}", isLog, isScreen)

proc writeLspInitialized*(
    commandLine: CommandLine, command: Runes, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.lspLogNotify
    isScreen = settings.screenNotifications and settings.lspScreenNotify

  if isLog or isScreen:
    commandLine.writeLspStandard(fmt"Client initialized: {command}", isLog, isScreen)

proc writeLspProgress*(
    commandLine: CommandLine, message: string, settings: NotificationSettings
) =
  let
    isLog = settings.logNotifications and settings.lspLogNotify
    isScreen = settings.screenNotifications and settings.lspScreenNotify

  if isLog or isScreen:
    commandLine.writeLspStandard(
      fmt"Progress: {message}", log = isLog, screen = isScreen
    )

proc writeLspInitializeError*(
    commandLine: CommandLine, command: Runes, errorMessage: string
) {.inline.} =
  commandLine.writeLspError(fmt"Client initialize failed: {command}: {errorMessage}")

proc writeLspHoverError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Hover failed: {message}")

proc writeLspCompletionError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Completion failed: {message}")

proc writeLspSemanticTokensError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeLspError(fmt"SemanticTokens failed: {message}")

proc writeLspInlayHintError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"InlayHint failed: {message}")

proc writeLspInlineValueError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Inline value failed: {message}")

proc writeLspSignatureHelpError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"SignatureHelp failed: {message}")

proc writeLspDocumentFormattingHelpError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeLspError(fmt"Document formatting failed: {message}")

proc writeLspDeclarationError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Declaration failed: {message}")

proc writeLspDefinitionError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Definition failed: {message}")

proc writeLspTypeDefinitionError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeLspError(fmt"TypeDefinition failed: {message}")

proc writeLspImplementationError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeLspError(fmt"Implementation failed: {message}")

proc writeLspReferencesError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"References failed: {message}")

proc writeLspCallHierarchyError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Call hierarchy failed: {message}")

proc writeLspDocumentHighlightError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeLspError(fmt"Document highlight failed: {message}")

proc writeLspDocumentLinkError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Document link failed: {message}")

proc writeLspCodeLensError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Code lens failed: {message}")

proc writeLspRenameError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Rename failed: {message}")

proc writeLspExecuteCommandError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeLspError(fmt"Execute command: {message}")

proc writeLspFoldingRangeError*(commandLine: CommandLine, message: string) {.inline.} =
  commandLine.writeLspError(fmt"Folding range: {message}")

proc writeLspSelectionRangeError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeLspError(fmt"Selection range: {message}")

proc writeLspDocumentSymbolError*(
    commandLine: CommandLine, message: string
) {.inline.} =
  commandLine.writeLspError(fmt"Document symbol: {message}")
