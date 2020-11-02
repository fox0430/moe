import strformat, os
import color, unicodetext, settings, commandline

proc writeMessageOnCommandWindow*(commandLine: var CommandLine,
                                  message: string,
                                  color: EditorColorPair) {.inline.} =
  commandLine.updateCommandBuffer(ru message, color)

proc writeMessageOnCommandWindow*(commandLine: var CommandLine,
                                  message: string) {.inline.} =
  commandLine.writeMessageOnCommandWindow(message, EditorColorPair.commandBar)

proc writeNoWriteError*(commandLine: var CommandLine, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: No write since last change"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeSaveError*(commandLine: var CommandLine, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Failed to save the file"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeRemoveFileError*(commandLine: var CommandLine, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Can not remove file"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeRemoveDirError*(commandLine: var CommandLine, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Can not remove directory"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeCopyFileError*(commandLine: var CommandLine, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Can not copy file"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeFileOpenError*(commandLine: var CommandLine,
                         fileName: string,
                         messageLog: var seq[seq[Rune]]) =

  let mess = "Error: Can not open: " & fileName
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeCreateDirError*(commandLine: var CommandLine, messageLog: var seq[seq[Rune]]) {.inline.} =
  const mess = "Error: Can not create directory"
  messageLog.add(mess.toRunes)

proc writeMessageDeletedFile*(commandLine: var CommandLine,
                              filename: string,
                              settings: NotificationSettings,
                              messageLog: var seq[seq[Rune]]) =

  let mess = "Deleted: " & filename
  if settings.screenNotifications and settings.filerScreenNotify:
    commandLine.writeMessageOnCommandWindow(mess)
  if settings.logNotifications and settings.filerLogNotify:
    messageLog.add(mess.toRunes)

proc writeNoFileNameError*(commandLine: var CommandLine, messageLog: var seq[seq[Rune]]) =

  let mess = "Error: No file name"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeMessageYankedLine*(commandLine: var CommandLine,
                             numOfLine: int,
                             settings: NotificationSettings,
                             messageLog: var seq[seq[Rune]]) =

  let mess = fmt"{numOfLine} line(s) yanked"
  if settings.screenNotifications and settings.yankScreenNotify:
    commandLine.writeMessageOnCommandWindow(mess)
  if settings.logNotifications and settings.yankLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageYankedCharactor*(commandLine: var CommandLine,
                                  numOfChar: int,
                                  settings: NotificationSettings,
                                  messageLog: var seq[seq[Rune]]) =

  let mess = fmt"{numOfChar} character(s) yanked"
  if settings.screenNotifications and settings.yankScreenNotify:
    commandLine.writeMessageOnCommandWindow(mess)
  if settings.yankLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageAutoSave*(commandLine: var CommandLine,
                           filename: seq[Rune],
                           settings: NotificationSettings,
                           messageLog: var seq[seq[Rune]]) =

  let mess = fmt"Auto saved {filename}"
  if settings.screenNotifications and settings.autoSaveScreenNotify:
    let mess = fmt"Auto saved {filename}"
    commandLine.writeMessageOnCommandWindow(mess)
  if settings.logNotifications and settings.autoSaveLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageBuildOnSave*(commandLine: var CommandLine,
                              settings: NotificationSettings,
                              messageLog: var seq[seq[Rune]]) =

  const mess = "Build on save..."
  if settings.screenNotifications and settings.buildOnSaveScreenNotify:
    commandLine.writeMessageOnCommandWindow(mess)
  if settings.logNotifications and settings.buildOnSaveLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageSuccessBuildOnSave*(commandLine: var CommandLine,
                                     settings: NotificationSettings,
                                     messageLog: var seq[seq[Rune]]) =

  const mess = "Build successful, file saved"
  if settings.screenNotifications and settings.buildOnSaveScreenNotify:
    commandLine.writeMessageOnCommandWindow(mess)
  if settings.logNotifications and settings.buildOnSaveLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageFailedBuildOnSave*(commandLine: var CommandLine, messageLog: var seq[seq[Rune]]) =
  const mess = "Build failed"
  commandLine.writeMessageOnCommandWindow(mess)
  messageLog.add(mess.toRunes)

proc writeNotEditorCommandError*(commandLine: var CommandLine,
                                 command: seq[seq[Rune]],
                                 messageLog: var seq[seq[Rune]]) =

  var cmd = ""
  for i in 0 ..< command.len: cmd = cmd & $command[i] & " "
  let mess = fmt"Error: Not an editor command: {cmd}"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeMessageSaveFile*(commandLine: var CommandLine,
                           filename: seq[Rune],
                           settings: NotificationSettings,
                           messageLog: var seq[seq[Rune]]) =


  let mess = fmt"Saved {filename}"
  if settings.screenNotifications and settings.saveScreenNotify:
    commandLine.writeMessageOnCommandWindow(mess)
  if settings.logNotifications and settings.saveLogNotify:
    messageLog.add(mess.toRunes)

proc writeNoBufferDeletedError*(commandLine: var CommandLine,
                                messageLog: var seq[seq[Rune]]) =

  let mess = "Error: No buffers were deleted"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writePutConfigFileError*(commandLine: var CommandLine,
                              messageLog: var seq[seq[Rune]]) =

  const mess = "Error: Failed to put configuration file"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writePutConfigFileAlreadyExistError*(commandLine: var CommandLine,
                                          messageLog: var seq[seq[Rune]]) =

  const mess = "Error: Configuration file already exists"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeOpenRecentlyUsedXbelError*(commandLine: var CommandLine,
                                     messageLog: var seq[seq[Rune]]) =

  const mess = "Error: " & getHomeDir() / ".local/share/recently-used.xbel" & " Not found"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeFileNotFoundError*(commandLine: var CommandLine,
                             filename: seq[Rune],
                             messageLog: var seq[seq[Rune]]) =

  let mess = "Error: " & $filename & " not found"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeStartAutoBackupMessage*(commandLine: var CommandLine,
                                  settings: NotificationSettings,
                                  messageLog: var seq[seq[Rune]]) =

  const mess = "Start automatic backup..."
  if settings.screenNotifications and settings.autoBackupScreenNotify:
    commandLine.writeMessageOnCommandWindow(mess)
  if settings.logNotifications and settings.autoBackupLogNotify:
    messageLog.add(mess.toRunes)

proc writeAutoBackupSuccessMessage*(commandLine: var CommandLine,
                                    message: string,
                                    settings: NotificationSettings,
                                    messageLog: var seq[seq[Rune]]) =

  if settings.screenNotifications and settings.autoBackupScreenNotify:
    commandLine.writeMessageOnCommandWindow(message)
  if settings.logNotifications and settings.autoBackupLogNotify:
    messageLog.add(message.toRunes)

proc writeAutoBackupFailedMessage*(commandLine: var CommandLine,
                                   filename: seq[Rune],
                                   settings: NotificationSettings,
                                   messageLog: var seq[seq[Rune]]) =

  let message = fmt"Error: Automatic backups failed: {$filename}"
  if settings.screenNotifications and settings.autoBackupScreenNotify:
    commandLine.writeMessageOnCommandWindow(message, EditorColorPair.errorMessage)
  if settings.logNotifications and settings.autoBackupLogNotify:
    messageLog.add(message.toRunes)

proc writeRunQuickRunMessage*(commandLine: var CommandLine,
                              settings: NotificationSettings,
                              messageLog: var seq[seq[Rune]]) =

  const mess = "Quick run..."
  if settings.quickRunScreenNotify:
    commandLine.writeMessageOnCommandWindow(mess)

proc writeRunQuickRunTimeoutMessage*(commandLine: var CommandLine,
                                     messageLog: var seq[seq[Rune]]) =

  const mess = "Quick run timeout"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeRunQuickRunFailedMessage*(commandLine: var CommandLine, messageLog: var seq[seq[Rune]]) =
  const mess = "Quick run failed"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeInvalidItemInConfigurationFileError*(commandLine: var CommandLine,
                           message: string,
                           messageLog: var seq[seq[Rune]]) =

  let mess = "Error: Failed to load configuration file: Invalid item: " &
             message
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(message.toRunes)

proc writeFailedToLoadConfigurationFileError*(commandLine: var CommandLine,
                           message: string,
                           messageLog: var seq[seq[Rune]]) =
  let mess = fmt"Error: Failed to load configuration file: {message}"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(message.toRunes)

proc writeNotExistWorkspaceError*(commandLine: var CommandLine,
                                  workspaceIndex: int,
                                  messageLog: var seq[seq[Rune]]) =

  let mess = "Error: Workspace " & $workspaceIndex & " not exist"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)

proc writeWorkspaceList*(commandLine: var CommandLine, buffer: string) {.inline.} =
  commandLine.writeMessageOnCommandWindow(buffer, EditorColorPair.commandBar)

proc writeBackupRestoreError*(commandLine: var CommandLine) {.inline.} =
  const mess = "Error: Restore failed"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)

proc writeRestoreFileSuccessMessage*(commandLine: var CommandLine,
                                     filename: seq[Rune],
                                     settings: NotificationSettings,
                                     messageLog: var seq[seq[Rune]]) =

  let message = fmt"Restore successful {filename}"
  if settings.screenNotifications and settings.restoreScreenNotify:
    commandLine.writeMessageOnCommandWindow(message)
  if settings.logNotifications and settings.restoreLogNotify:
    messageLog.add(message.toRunes)

proc writeDeleteBackupError*(commandLine: var CommandLine) {.inline.} =
  const mess = "Error: Delete backup file failed"
  commandLine.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
