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
    commandLine.writeMessageOnCommandLine(message, EditorColorPairIndex.commandBar)

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
  const mess = "Error: Can not create directory"
  addMessageLog mess

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
  filename: seq[Rune],
  settings: NotificationSettings) =
    let mess = fmt"Auto saved {filename}"
    if settings.screenNotifications and settings.autoSaveScreenNotify:
      let mess = fmt"Auto saved {filename}"
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.autoSaveLogNotify:
      addMessageLog mess

proc writeMessageBuildOnSave*(
  commandLine: var CommandLine,
  settings: NotificationSettings) =
    const mess = "Build on save..."
    if settings.screenNotifications and settings.buildOnSaveScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.buildOnSaveLogNotify:
      addMessageLog mess

proc writeMessageSuccessBuildOnSave*(
  commandLine: var CommandLine,
  settings: NotificationSettings) =
    const mess = "Build successful, file saved"
    if settings.screenNotifications and settings.buildOnSaveScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.buildOnSaveLogNotify:
      addMessageLog mess

proc writeMessageFailedBuildOnSave*(commandLine: var CommandLine) =
  const mess = "Build failed"
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
  filename: seq[Rune],
  settings: NotificationSettings) =
    let mess = fmt"Saved {filename}"
    if settings.screenNotifications and settings.saveScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.saveLogNotify:
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
  const mess = "Error: Failed to put configuration file"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writePutConfigFileAlreadyExistError*(commandLine: var CommandLine) =
  const mess = "Error: Configuration file already exists"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeOpenRecentlyUsedXbelError*(commandLine: var CommandLine) =
  const mess =
    "Error: " &
    getHomeDir() / ".local/share/recently-used.xbel" &
    " Not found"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeFileNotFoundError*(
  commandLine: var CommandLine,
  filename: seq[Rune]) =
    let mess = "Error: " & $filename & " not found"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
    addMessageLog mess

proc writeStartAutoBackupMessage*(
  commandLine: var CommandLine,
  settings: NotificationSettings) =
    const mess = "Start automatic backup..."
    if settings.screenNotifications and settings.autoBackupScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.autoBackupLogNotify:
      addMessageLog mess

proc writeAutoBackupSuccessMessage*(
  commandLine: var CommandLine,
  message: string,
  settings: NotificationSettings) =
    if settings.screenNotifications and settings.autoBackupScreenNotify:
      commandLine.writeMessageOnCommandLine(message)
    if settings.logNotifications and settings.autoBackupLogNotify:
      addMessageLog message

proc writeAutoBackupFailedMessage*(
  commandLine: var CommandLine,
  filename: seq[Rune],
  settings: NotificationSettings) =
    let message = fmt"Error: Automatic backups failed: {$filename}"
    if settings.screenNotifications and settings.autoBackupScreenNotify:
      commandLine.writeMessageOnCommandLine(message, EditorColorPairIndex.errorMessage)
    if settings.logNotifications and settings.autoBackupLogNotify:
      addMessageLog message

proc writeRunQuickRunMessage*(
  commandLine: var CommandLine,
  settings: NotificationSettings) =
    const mess = "Quick run..."
    if settings.quickRunScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)

proc writeRunQuickRunTimeoutMessage*(commandLine: var CommandLine) =
    const mess = "Quick run timeout"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
    addMessageLog mess

proc writeRunQuickRunFailedMessage*(commandLine: var CommandLine) =
    const mess = "Quick run failed"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
    addMessageLog mess

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
  const mess = "Error: Restore failed"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)

proc writeRestoreFileSuccessMessage*(
  commandLine: var CommandLine,
  filename: seq[Rune],
  settings: NotificationSettings) =
    let message = fmt"Restore successful {filename}"
    if settings.screenNotifications and settings.restoreScreenNotify:
      commandLine.writeMessageOnCommandLine(message)
    if settings.logNotifications and settings.restoreLogNotify:
      addMessageLog message

proc writeDeleteBackupError*(commandLine: var CommandLine) {.inline.} =
  const mess = "Error: Delete backup file failed"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
  addMessageLog mess

proc writeExitHelp*(commandLine: var CommandLine) {.inline.} =
  const mess = "Type  :qa  and press <Enter> to exit moe"
  commandLine.writeMessageOnCommandLine(mess)

proc writeCurrentCharInfo*(commandLine: var CommandLine, r: Rune) {.inline.} =
  let
    e = encodeUTF8(r)
    eHex = e[0].toHex
    eOct = int64(e[0]).toOct(5)
    mess = fmt "<{$r}>  {e[0]}  Hex {normalizeHex($eHex)}  Oct {$eOct}"
  commandLine.writeMessageOnCommandLine(mess)

proc writeReadonlyModeWarning*(commandLine: var CommandLine) {.inline.} =
  const mess = "Warning: Readonly mode"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)

proc writeManualCommandError*(
  commandLine: var CommandLine,
  message: string) {.inline.} =
    let mess = fmt"Error: No manual entry for {message}"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
    addMessageLog mess

proc writeSyntaxCheckError*(
  commandLine: var CommandLine,
  message: string) {.inline.} =

    let mess = fmt"Error: Syntax check failed: {message}"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPairIndex.errorMessage)
    addMessageLog mess
