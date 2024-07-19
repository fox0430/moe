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

import std/[strformat, os, strutils]
import color, unicodeext, settings, commandline, independentutils, messagelog

proc writeMessageOnCommandLine*(
  commandLine: var CommandLine,
  message: string,
  color: EditorColorPairIndex) {.inline.} =
    commandLine.write(message.toRunes)
    commandLine.setColor(color)

proc writeMessageOnCommandLine*(
  commandLine: var CommandLine,
  message: string) {.inline.} =
    commandLine.writeMessageOnCommandLine(message, EditorColorPairIndex.commandLine)

proc writeStandard*(c: var CommandLine, message: string) =
  c.writeMessageOnCommandLine(message, EditorColorPairIndex.commandLine)
  addMessageLog message

proc writeInfo*(c: var CommandLine, message: string) =
  let mess = fmt"INFO: {message}"
  c.writeMessageOnCommandLine(mess, EditorColorPairIndex.commandLine)
  addMessageLog message

proc writeLog*(c: var CommandLine, message: string) =
  let mess = fmt"LOG: {message}"
  c.writeMessageOnCommandLine(mess, EditorColorPairIndex.commandLine)
  addMessageLog message

proc writeDebug*(c: var CommandLine, message: string) =
  let mess = fmt"DEBUG: {message}"
  c.writeMessageOnCommandLine(mess, EditorColorPairIndex.commandLine)
  addMessageLog message

proc writeError*(c: var CommandLine, message: string) =
  # TODO: Add "Error:" prefix.
  c.writeMessageOnCommandLine(message, EditorColorPairIndex.errorMessage)
  addMessageLog message

proc writeWarn*(c: var CommandLine, message: string) =
  let mess = fmt"WARN: {message}"
  c.writeMessageOnCommandLine(mess, EditorColorPairIndex.warnMessage)
  addMessageLog message

proc writeNoWriteError*(commandLine: var CommandLine) =
  let mess = "Error: No write since last change"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeSaveError*(commandLine: var CommandLine) =
  let mess = "Error: Failed to save the file"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeRemoveFileError*(commandLine: var CommandLine) =
  let mess = "Error: Can not remove file"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeRemoveDirError*(commandLine: var CommandLine) =
  let mess = "Error: Can not remove directory"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeCopyFileError*(commandLine: var CommandLine) =
  let mess = "Error: Can not copy file"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeFileOpenError*(commandLine: var CommandLine, fileName: string) =
  let mess = "Error: Can not open: " & fileName
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeCreateDirError*(commandLine: var CommandLine) {.inline.} =
  const Mess = "Error: Can not create directory"
  addMessageLog Mess

proc writeMessageDeletedFile*(
  commandLine: var CommandLine,
  filename: string,
  settings: NotificationSettings) =
    let mess = "Deleted: " & filename
    if settings.screenNotifications and settings.filerScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.filerLogNotify:
      addMessageLog mess

proc writeNoFileNameError*(commandLine: var CommandLine) =
  let mess = "Error: No file name"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeMessageYankedLine*(
  commandLine: var CommandLine,
  numOfLine: int,
  settings: NotificationSettings) =
    let mess = fmt"{numOfLine} line(s) yanked"
    if settings.screenNotifications and settings.yankScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.yankLogNotify:
      addMessageLog mess

proc writeMessageYankedCharactor*(
  commandLine: var CommandLine,
  numOfChar: int,
  settings: NotificationSettings) =
    let mess = fmt"{numOfChar} character(s) yanked"
    if settings.screenNotifications and settings.yankScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.yankLogNotify:
      addMessageLog mess

proc writeMessageAutoSave*(
  commandLine: var CommandLine,
  filename: Runes,
  settings: NotificationSettings) =
    let mess = fmt"Auto saved {filename}"
    if settings.screenNotifications and settings.autoSaveScreenNotify:
      let mess = fmt"Auto saved {filename}"
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.autoSaveLogNotify:
      addMessageLog mess

proc writeMessageSuccessBuildOnSave*(
  commandLine: var CommandLine,
  path: Runes,
  settings: NotificationSettings) =

    let mess = fmt"Build on save successful: {$path}"
    if settings.screenNotifications and settings.buildOnSaveScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.buildOnSaveLogNotify:
      addMessageLog mess

proc writeMessageFailedBuildOnSave*(commandLine: var CommandLine, path: Runes) =
  let mess = fmt"Build failed: {$path}"
  commandLine.writeMessageOnCommandLine(mess)
  addMessageLog mess

proc writeNotEditorCommandError*(
  commandLine: var CommandLine,
  command: Runes) =
    let mess = fmt"Error: Not an editor command: {command}"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
    addMessageLog mess

proc writeNotEditorCommandError*(
  commandLine: var CommandLine,
  command: seq[Runes]) {.inline.} =
    commandLine.writeNotEditorCommandError(command.join(ru" "))

proc writeMessageSaveFile*(
  commandLine: var CommandLine,
  filename: Runes,
  settings: NotificationSettings) =

    let mess = fmt"Saved {filename}"
    if settings.screenNotifications and settings.saveScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.saveLogNotify:
      addMessageLog mess

proc writeMessageSaveFileAndStartBuild*(
  commandLine: var CommandLine,
  filename: Runes,
  settings: NotificationSettings) =

    let mess = fmt"Saved {filename} and start build..."
    if settings.screenNotifications and settings.buildOnSaveScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.buildOnSaveLogNotify:
      addMessageLog mess

proc writeNoBufferDeletedError*(commandLine: var CommandLine) =
  let mess = "Error: No buffers were deleted"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writePutConfigFile*(commandLine: var CommandLine, configPath: string) =
  let mess = fmt "Wrote the current editor settings to {$configPath}"
  commandLine.writeMessageOnCommandLine(mess)
  addMessageLog mess

proc writePutConfigFileError*(commandLine: var CommandLine) =
  const Mess = "Error: Failed to put configuration file"
  commandLine.writeMessageOnCommandLine(Mess, EditorColorPairIndex.errorMessage)
  addMessageLog Mess

proc writePutConfigFileAlreadyExistError*(commandLine: var CommandLine) =
  const Mess = "Error: Configuration file already exists"
  commandLine.writeMessageOnCommandLine(Mess, EditorColorPairIndex.errorMessage)
  addMessageLog Mess

proc writeOpenRecentlyUsedXbelError*(commandLine: var CommandLine) =
  const Mess =
    "Error: " &
    getHomeDir() / ".local/share/recently-used.xbel" &
    " Not found"
  commandLine.writeMessageOnCommandLine(Mess, EditorColorPairIndex.errorMessage)
  addMessageLog Mess

proc writeFileNotFoundError*(
  commandLine: var CommandLine,
  filename: Runes) =
    let mess = "Error: " & $filename & " not found"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
    addMessageLog mess

proc writeStartAutoBackupMessage*(
  commandLine: var CommandLine,
  settings: NotificationSettings) =
    const Mess = "Start automatic backup..."
    if settings.screenNotifications and settings.autoBackupScreenNotify:
      commandLine.writeMessageOnCommandLine(Mess)
    if settings.logNotifications and settings.autoBackupLogNotify:
      addMessageLog Mess

proc writeAutoBackupSuccessMessage*(
  commandLine: var CommandLine,
  message: string,
  settings: NotificationSettings) =
    if settings.screenNotifications and settings.autoBackupScreenNotify:
      commandLine.writeMessageOnCommandLine(message)
    if settings.logNotifications and settings.autoBackupLogNotify:
      addMessageLog message

proc writeRunQuickRunMessage*(
  commandLine: var CommandLine,
  settings: NotificationSettings) =
    const Mess = "Quick run..."
    if settings.quickRunScreenNotify:
      commandLine.writeMessageOnCommandLine(Mess)

proc writeInRecordingOperations*(
  commandLine: var CommandLine,
  registerName: Rune) =

    let mess = fmt"recording @{$registerName}"
    commandLine.writeMessageOnCommandLine(mess)
    addMessageLog mess

proc writeLspInitialized*(commandLine: var CommandLine, command: Runes) =
  let mess = fmt"LSP client initialized: {$command}"
  commandLine.writeMessageOnCommandLine(mess)
  addMessageLog mess

proc writeAutoBackupFailedMessage*(
  commandLine: var CommandLine,
  filename: Runes,
  settings: NotificationSettings) =
    let message = fmt"Error: Automatic backups failed: {$filename}"
    if settings.screenNotifications and settings.autoBackupScreenNotify:
      commandLine.writeMessageOnCommandLine(message, EditorColorPairIndex.errorMessage)
    if settings.logNotifications and settings.autoBackupLogNotify:
      addMessageLog message

proc writeRunQuickRunTimeoutMessage*(commandLine: var CommandLine) =
    const Mess = "Quick run timeout"
    commandLine.writeMessageOnCommandLine(Mess, EditorColorPairIndex.errorMessage)
    addMessageLog Mess

proc writeRunQuickRunFailedMessage*(commandLine: var CommandLine) =
    const Mess = "Quick run failed"
    commandLine.writeMessageOnCommandLine(Mess, EditorColorPairIndex.errorMessage)
    addMessageLog Mess

proc writeInvalidItemInConfigurationFileError*(
  commandLine: var CommandLine,
  message: string) =
    let mess = "Error: Failed to load configuration file: Invalid item: " &
               message
    commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
    addMessageLog message

proc writeFailedToLoadConfigurationFileError*(
  commandLine: var CommandLine,
  message: string) =
    let mess = fmt"Error: Failed to load configuration file: {message}"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
    addMessageLog mess

proc writeBackupRestoreError*(commandLine: var CommandLine) {.inline.} =
  const Mess = "Error: Restore failed"
  commandLine.writeMessageOnCommandLine(Mess, EditorColorPairIndex.errorMessage)

proc writeRestoreFileSuccessMessage*(
  commandLine: var CommandLine,
  filename: Runes,
  settings: NotificationSettings) =
    let message = fmt"Restore successful {filename}"
    if settings.screenNotifications and settings.restoreScreenNotify:
      commandLine.writeMessageOnCommandLine(message)
    if settings.logNotifications and settings.restoreLogNotify:
      addMessageLog message

proc writeDeleteBackupError*(commandLine: var CommandLine) {.inline.} =
  const Mess = "Error: Delete backup file failed"
  commandLine.writeMessageOnCommandLine(Mess, EditorColorPairIndex.errorMessage)
  addMessageLog Mess

proc writeExitHelp*(commandLine: var CommandLine) {.inline.} =
  const Mess = "Type  :qa  and press <Enter> to exit moe"
  commandLine.writeMessageOnCommandLine(Mess)

proc writeCurrentCharInfo*(commandLine: var CommandLine, r: Rune) {.inline.} =
  let
    e = encodeUTF8(r)
    eHex = e[0].uint64.toHex
    eOct = int64(e[0]).toOct(5)
    mess = fmt "<{$r}>  {e[0]}  Hex {normalizeHex($eHex)}  Oct {$eOct}"
  commandLine.writeMessageOnCommandLine(mess)

proc writeReadonlyModeWarning*(commandLine: var CommandLine) {.inline.} =
  const Mess = "Readonly mode"
  commandLine.writeWarn(Mess)

proc writeManualCommandError*(
  commandLine: var CommandLine,
  message: string) {.inline.} =

    let mess = fmt"Error: No manual entry for {message}"
    commandLine.writeMessageOnCommandLine(
      mess,
      EditorColorPairIndex.errorMessage)
    addMessageLog mess

proc writeSyntaxCheckError*(
  commandLine: var CommandLine,
  message: string) {.inline.} =

    let mess = fmt"Error: Syntax check failed: {message}"
    commandLine.writeMessageOnCommandLine(
      mess,
      EditorColorPairIndex.errorMessage)
    addMessageLog mess

proc writeGitInfoUpdateError*(commandLine: var CommandLine, message: string) =
  let mess = fmt"Error: Update Git info: {message}"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeBufferChangedWarn*(commandLine: var CommandLine, filename: Runes) =
  let mess = fmt"File {filename} has changed and the buffer was changed in Moe as well."
  commandLine.writeWarn(mess)

proc writeLspError*(commandLine: var CommandLine, message: string) =
  let mess = fmt"lsp: {message}"
  commandLine.writeError(mess)
  addMessageLog mess

proc writeLspInitializeError*(
  commandLine: var CommandLine,
  command: Runes,
  errorMessage: string) =

    let mess = fmt"lsp: client initialize failed: {$command}: {errorMessage}"
    commandLine.writeMessageOnCommandLine(
      mess,
      EditorColorPairIndex.errorMessage)
    addMessageLog mess

proc writeLspHoverError*(commandLine: var CommandLine, message: string) =
  let mess = fmt"lsp: Error: hover failed: {message}"
  commandLine.writeError(mess)

proc writeLspCompletionError*(commandLine: var CommandLine, message: string) =
  let mess = fmt"lsp: Error: completion failed: {message}"
  commandLine.writeError(mess)

proc writeLspSemanticTokensError*(
  commandLine: var CommandLine,
  message: string) =

    let mess = fmt"lsp: Error: semanticTokens failed: {message}"
    commandLine.writeError(mess)

proc writeLspInlayHintError*(commandLine: var CommandLine, message: string) =
  let mess = fmt"lsp: Error: inlayHint failed: {message}"
  commandLine.writeError(mess)

proc writeLspDeclarationError*(commandLine: var CommandLine, message: string) =
  let mess = fmt"lsp: Error: declaration failed: {message}"
  commandLine.writeError(mess)

proc writeLspDefinitionError*(commandLine: var CommandLine, message: string) =
  let mess = fmt"lsp: Error: definition failed: {message}"
  commandLine.writeError(mess)

proc writeLspTypeDefinitionError*(
  commandLine: var CommandLine,
  message: string) =

    let mess = fmt"lsp: Error: typeDefinition failed: {message}"
    commandLine.writeError(mess)

proc writeLspImplementationError*(
  commandLine: var CommandLine,
  message: string) =

    let mess = fmt"lsp: Error: implementation failed: {message}"
    commandLine.writeError(mess)

proc writeLspReferencesError*(commandLine: var CommandLine, message: string) =
  let mess = fmt"lsp: Error: references failed: {message}"
  commandLine.writeError(mess)

proc writeLspCallHierarchyError*(
  commandLine: var CommandLine, message: string) =
    let mess = fmt"lsp: Error: call hierarchy failed: {message}"
    commandLine.writeError(mess)

proc writeLspDocumentHighlightError*(
  commandLine: var CommandLine, message: string) =
    let mess = fmt"lsp: Error: document highlight failed: {message}"
    commandLine.writeError(mess)

proc writeLspDocumentLinkError*(
  commandLine: var CommandLine, message: string) =
    let mess = fmt"lsp: Error: document link failed: {message}"
    commandLine.writeError(mess)

proc writeLspCodeLensError*(
  commandLine: var CommandLine, message: string) =
    let mess = fmt"lsp: Error: code lens failed: {message}"
    commandLine.writeError(mess)

proc writeLspRenameError*(commandLine: var CommandLine, message: string) =
  let mess = fmt"lsp: Error: renamefailed: {message}"
  commandLine.writeError(mess)

proc writeLspExecuteCommandError*(
  commandLine: var CommandLine,
  message: string) =

    let mess = fmt"lsp: Error: execute commnad: {message}"
    commandLine.writeError(mess)

proc writePasteIgnoreWarn*(commandLine: var CommandLine) =
  const Mess = "Paste is ignored in this mode"
  commandLine.writeWarn(Mess)

proc writeLspServerError*(commandLine: var CommandLine, message: string) =
  commandLine.writeError(fmt"ERR: lsp: {message}")

proc writeLspServerWarn*(commandLine: var CommandLine, message: string) =
  commandLine.writeWarn(fmt"lsp: {message}")

proc writeLspServerInfo*(commandLine: var CommandLine, message: string) =
  commandLine.writeInfo(fmt"lsp: {message}")

proc writeLspServerLog*(commandLine: var CommandLine, message: string) =
  commandLine.writeLog(fmt"lsp: {message}")

proc writeLspServerDebug*(commandLine: var CommandLine, message: string) =
  commandLine.writeDebug(fmt"lsp: {message}")

proc writeLspProgress*(commandLine: var CommandLine, message: string) =
  commandLine.writeStandard(fmt"lsp: progress: {message}")
