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
import color, unicodeext, settings, commandline, independentutils

proc writeMessageOnCommandLine*(
  commandLine: var CommandLine,
  message: string,
  color: EditorColorPair) {.inline.} =
    commandLine.write(message.toRunes)
    commandLine.setColor(color)

proc writeMessageOnCommandLine*(
  commandLine: var CommandLine,
  message: string) {.inline.} =
    commandLine.writeMessageOnCommandLine(message, EditorColorPair.commandBar)

proc writeNoWriteError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    let mess = "Error: No write since last change"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeSaveError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    let mess = "Error: Failed to save the file"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeRemoveFileError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    let mess = "Error: Can not remove file"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeRemoveDirError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    let mess = "Error: Can not remove directory"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeCopyFileError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    let mess = "Error: Can not copy file"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeFileOpenError*(
  commandLine: var CommandLine,
  fileName: string,
  messageLog: var seq[Runes]) =
    let mess = "Error: Can not open: " & fileName
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeCreateDirError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) {.inline.} =
    const mess = "Error: Can not create directory"
    messageLog.add(mess.toRunes)

proc writeMessageDeletedFile*(
  commandLine: var CommandLine,
  filename: string,
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    let mess = "Deleted: " & filename
    if settings.screenNotifications and settings.filerScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.filerLogNotify:
      messageLog.add(mess.toRunes)

proc writeNoFileNameError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    let mess = "Error: No file name"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeMessageYankedLine*(
  commandLine: var CommandLine,
  numOfLine: int,
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    let mess = fmt"{numOfLine} line(s) yanked"
    if settings.screenNotifications and settings.yankScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.yankLogNotify:
      messageLog.add(mess.toRunes)

proc writeMessageYankedCharactor*(
  commandLine: var CommandLine,
  numOfChar: int,
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    let mess = fmt"{numOfChar} character(s) yanked"
    if settings.screenNotifications and settings.yankScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.yankLogNotify:
      messageLog.add(mess.toRunes)

proc writeMessageAutoSave*(
  commandLine: var CommandLine,
  filename: seq[Rune],
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    let mess = fmt"Auto saved {filename}"
    if settings.screenNotifications and settings.autoSaveScreenNotify:
      let mess = fmt"Auto saved {filename}"
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.autoSaveLogNotify:
      messageLog.add(mess.toRunes)

proc writeMessageBuildOnSave*(
  commandLine: var CommandLine,
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    const mess = "Build on save..."
    if settings.screenNotifications and settings.buildOnSaveScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.buildOnSaveLogNotify:
      messageLog.add(mess.toRunes)

proc writeMessageSuccessBuildOnSave*(
  commandLine: var CommandLine,
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    const mess = "Build successful, file saved"
    if settings.screenNotifications and settings.buildOnSaveScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.buildOnSaveLogNotify:
      messageLog.add(mess.toRunes)

proc writeMessageFailedBuildOnSave*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    const mess = "Build failed"
    commandLine.writeMessageOnCommandLine(mess)
    messageLog.add(mess.toRunes)

proc writeNotEditorCommandError*(
  commandLine: var CommandLine,
  command: seq[Runes],
  messageLog: var seq[Runes]) =
    var cmd = ""
    for i in 0 ..< command.len: cmd = cmd & $command[i] & " "
    let mess = fmt"Error: Not an editor command: {cmd}"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeMessageSaveFile*(
  commandLine: var CommandLine,
  filename: seq[Rune],
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    let mess = fmt"Saved {filename}"
    if settings.screenNotifications and settings.saveScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.saveLogNotify:
      messageLog.add(mess.toRunes)

proc writeNoBufferDeletedError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    let mess = "Error: No buffers were deleted"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writePutConfigFile*(
  commandLine: var CommandLine,
  configPath: string,
  messageLog: var seq[Runes]) =
    let mess = fmt "Wrote the current editor settings to {$configPath}"
    commandLine.writeMessageOnCommandLine(mess)
    messageLog.add(mess.toRunes)

proc writePutConfigFileError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    const mess = "Error: Failed to put configuration file"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writePutConfigFileAlreadyExistError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    const mess = "Error: Configuration file already exists"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeOpenRecentlyUsedXbelError*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    const mess =
      "Error: " &
      getHomeDir() / ".local/share/recently-used.xbel" &
      " Not found"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeFileNotFoundError*(
  commandLine: var CommandLine,
  filename: seq[Rune],
  messageLog: var seq[Runes]) =
    let mess = "Error: " & $filename & " not found"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeStartAutoBackupMessage*(
  commandLine: var CommandLine,
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    const mess = "Start automatic backup..."
    if settings.screenNotifications and settings.autoBackupScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)
    if settings.logNotifications and settings.autoBackupLogNotify:
      messageLog.add(mess.toRunes)

proc writeAutoBackupSuccessMessage*(
  commandLine: var CommandLine,
  message: string,
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    if settings.screenNotifications and settings.autoBackupScreenNotify:
      commandLine.writeMessageOnCommandLine(message)
    if settings.logNotifications and settings.autoBackupLogNotify:
      messageLog.add(message.toRunes)

proc writeAutoBackupFailedMessage*(
  commandLine: var CommandLine,
  filename: seq[Rune],
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    let message = fmt"Error: Automatic backups failed: {$filename}"
    if settings.screenNotifications and settings.autoBackupScreenNotify:
      commandLine.writeMessageOnCommandLine(message, EditorColorPair.errorMessage)
    if settings.logNotifications and settings.autoBackupLogNotify:
      messageLog.add(message.toRunes)

proc writeRunQuickRunMessage*(
  commandLine: var CommandLine,
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    const mess = "Quick run..."
    if settings.quickRunScreenNotify:
      commandLine.writeMessageOnCommandLine(mess)

proc writeRunQuickRunTimeoutMessage*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    const mess = "Quick run timeout"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeRunQuickRunFailedMessage*(
  commandLine: var CommandLine,
  messageLog: var seq[Runes]) =
    const mess = "Quick run failed"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(mess.toRunes)

proc writeInvalidItemInConfigurationFileError*(
  commandLine: var CommandLine,
  message: string,
  messageLog: var seq[Runes]) =
    let mess = "Error: Failed to load configuration file: Invalid item: " &
               message
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(message.toRunes)

proc writeFailedToLoadConfigurationFileError*(
  commandLine: var CommandLine,
  message: string,
  messageLog: var seq[Runes]) =
    let mess = fmt"Error: Failed to load configuration file: {message}"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
    messageLog.add(message.toRunes)

proc writeNotExistWorkspaceError*(
  commandLine: var CommandLine,
  workspaceIndex: int,
  messageLog: var seq[Runes]) =
    let mess = "Error: Workspace " & $workspaceIndex & " not exist"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)

proc writeWorkspaceList*(
  commandLine: var CommandLine,
  buffer: string) {.inline.} =
    commandLine.writeMessageOnCommandLine(buffer, EditorColorPair.commandBar)

proc writeBackupRestoreError*(commandLine: var CommandLine) {.inline.} =
  const mess = "Error: Restore failed"
  commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)

proc writeRestoreFileSuccessMessage*(
  commandLine: var CommandLine,
  filename: seq[Rune],
  settings: NotificationSettings,
  messageLog: var seq[Runes]) =
    let message = fmt"Restore successful {filename}"
    if settings.screenNotifications and settings.restoreScreenNotify:
      commandLine.writeMessageOnCommandLine(message)
    if settings.logNotifications and settings.restoreLogNotify:
      messageLog.add(message.toRunes)

proc writeDeleteBackupError*(
  commandLine: var CommandLine) {.inline.} =
    const mess = "Error: Delete backup file failed"
    commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)

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
  commandLine.writeMessageOnCommandLine(mess, EditorColorPair.errorMessage)
