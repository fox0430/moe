import strformat, os
import ui, color, unicodeext, settings

proc writeMessageOnCommandWindow*(cmdWin: var Window,
                                 message: string,
                                 color: EditorColorPair) =

  cmdWin.erase
  cmdWin.write(0, 0, message, color)
  cmdWin.refresh

proc writeNoWriteError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: No write since last change"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeSaveError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Failed to save the file"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeRemoveFileError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Can not remove file"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeRemoveDirError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Can not remove directory"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeCopyFileError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Can not copy file"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeFileOpenError*(cmdWin: var Window,
                         fileName: string,
                         messageLog: var seq[seq[Rune]]) =

  let mess = "Error: Can not open: " & fileName
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeCreateDirError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) {.inline.} =
  const mess = "Error: Can not create directory"
  messageLog.add(mess.toRunes)

proc writeMessageDeletedFile*(cmdWin: var Window,
                              filename: string,
                              settings: NotificationSettings,
                              messageLog: var seq[seq[Rune]]) =

  let mess = "Deleted: " & filename
  if settings.screenNotifications and settings.filerScreenNotify:
    cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  if settings.logNotifications and settings.filerLogNotify:
    messageLog.add(mess.toRunes)

proc writeNoFileNameError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =

  let mess = "Error: No file name"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeMessageYankedLine*(cmdWin: var Window,
                             numOfLine: int,
                             settings: NotificationSettings,
                             messageLog: var seq[seq[Rune]]) =

  let mess = fmt"{numOfLine} line(s) yanked"
  if settings.screenNotifications and settings.yankScreenNotify:
    cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  if settings.logNotifications and settings.yankLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageYankedCharactor*(cmdWin: var Window,
                                  numOfChar: int,
                                  settings: NotificationSettings,
                                  messageLog: var seq[seq[Rune]]) =

  let mess = fmt"{numOfChar} character(s) yanked"
  if settings.screenNotifications and settings.yankScreenNotify:
    cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  if settings.yankLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageAutoSave*(cmdWin: var Window,
                           filename: seq[Rune],
                           settings: NotificationSettings,
                           messageLog: var seq[seq[Rune]]) =

  let mess = fmt"Auto saved {filename}"
  if settings.screenNotifications and settings.autoSaveScreenNotify:
    let mess = fmt"Auto saved {filename}"
    cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  if settings.logNotifications and settings.autoSaveLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageBuildOnSave*(cmdWin: var Window,
                              settings: NotificationSettings,
                              messageLog: var seq[seq[Rune]]) =

  const mess = "Build on save..."
  if settings.screenNotifications and settings.buildOnSaveScreenNotify:
    cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  if settings.logNotifications and settings.buildOnSaveLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageSuccessBuildOnSave*(cmdWin: var Window,
                                     settings: NotificationSettings,
                                     messageLog: var seq[seq[Rune]]) =

  const mess = "Build successful, file saved"
  if settings.screenNotifications and settings.buildOnSaveScreenNotify:
    cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  if settings.logNotifications and settings.buildOnSaveLogNotify:
    messageLog.add(mess.toRunes)

proc writeMessageFailedBuildOnSave*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  const mess = "Build failed"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeNotEditorCommandError*(cmdWin: var Window,
                                 command: seq[seq[Rune]],
                                 messageLog: var seq[seq[Rune]]) =

  var cmd = ""
  for i in 0 ..< command.len: cmd = cmd & $command[i] & " "
  let mess = fmt"Error: Not an editor command: {cmd}"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeMessageSaveFile*(cmdWin: var Window,
                           filename: seq[Rune],
                           settings: NotificationSettings,
                           messageLog: var seq[seq[Rune]]) =


  let mess = fmt"Saved {filename}"
  if settings.screenNotifications and settings.saveScreenNotify:
    cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  if settings.logNotifications and settings.saveLogNotify:
    messageLog.add(mess.toRunes)

proc writeNoBufferDeletedError*(cmdWin: var Window,
                                messageLog: var seq[seq[Rune]]) =

  let mess = "Error: No buffers were deleted"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writePutConfigFileError*(cmdWin: var Window,
                              messageLog: var seq[seq[Rune]]) =

  const mess = "Error: Failed to put configuration file"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writePutConfigFileAlreadyExistError*(cmdWin: var Window,
                                          messageLog: var seq[seq[Rune]]) =

  const mess = "Error: Configuration file already exists"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeOpenRecentlyUsedXbelError*(cmdWin: var Window,
                                     messageLog: var seq[seq[Rune]]) =

  const mess = "Error: " & getHomeDir() / ".local/share/recently-used.xbel" & " Not found"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeFileNotFoundError*(cmdWin: var Window,
                             filename: seq[Rune],
                             messageLog: var seq[seq[Rune]]) =

  let mess = "Error: " & $filename & " not found"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeStartAutoBackupMessage*(cmdWin: var Window,
                                  settings: NotificationSettings,
                                  messageLog: var seq[seq[Rune]]) =

  const mess = "Start automatic backup..."
  if settings.screenNotifications and settings.autoBackupScreenNotify:
    cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  if settings.logNotifications and settings.autoBackupLogNotify:
    messageLog.add(mess.toRunes)

proc writeAutoBackupSuccessMessage*(cmdWin: var Window,
                                    message: string,
                                    settings: NotificationSettings,
                                    messageLog: var seq[seq[Rune]]) =

  if settings.screenNotifications and settings.autoBackupScreenNotify:
    cmdWin.writeMessageOnCommandWindow(message, EditorColorPair.commandBar)
  if settings.logNotifications and settings.autoBackupLogNotify:
    messageLog.add(message.toRunes)

proc writeAutoBackupFailedMessage*(cmdWin: var Window,
                                   filename: seq[Rune],
                                   settings: NotificationSettings,
                                   messageLog: var seq[seq[Rune]]) =

  let message = fmt"Error: Automatic backups failed: {$filename}"
  if settings.screenNotifications and settings.autoBackupScreenNotify:
    cmdWin.writeMessageOnCommandWindow(message, EditorColorPair.errorMessage)
  if settings.logNotifications and settings.autoBackupLogNotify:
    messageLog.add(message.toRunes)

proc writeRunQuickRunMessage*(cmdWin: var Window,
                              settings: NotificationSettings,
                              messageLog: var seq[seq[Rune]]) =

  const mess = "Quick run..."
  if settings.quickRunScreenNotify:
    cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)

proc writeRunQuickRunTimeoutMessage*(cmdWin: var Window,
                                     messageLog: var seq[seq[Rune]]) =

  const mess = "Quick run timeout"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeRunQuickRunFailedMessage*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  const mess = "Quick run failed"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeInvalidItemInConfigurationFileError*(cmdWin: var Window,
                           message: string,
                           messageLog: var seq[seq[Rune]]) =

  let mess = "Error: Failed to load configuration file: Invalid item: " &
             message
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(message.toRunes)

proc writeFailedToLoadConfigurationFileError*(cmdWin: var Window,
                           message: string,
                           messageLog: var seq[seq[Rune]]) =
  let mess = fmt"Error: Failed to load configuration file: {message}"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(message.toRunes)

proc writeNotExistWorkspaceError*(cmdWin: var Window,
                                  workspaceIndex: int,
                                  messageLog: var seq[seq[Rune]]) =

  let mess = "Error: Workspace " & $workspaceIndex & " not exist"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)

proc writeWorkspaceList*(cmdWin: var Window, buffer: string) {.inline.} =
  cmdWin.writeMessageOnCommandWindow(buffer, EditorColorPair.commandBar)

<<<<<<< HEAD
proc writeBackupRestoreError*(cmdWin: var Window) {.inline.} =
=======
proc writeBackupRestoreError*(cmdWin: var Window) =
>>>>>>> ed2e9526d41a3062ed1edd5797c8ffcb990885e2
  const mess = "Error: Restore failed"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)

proc writeRestoreFileSuccessMessage*(cmdWin: var Window,
                                     filename: seq[Rune],
                                     settings: NotificationSettings,
                                     messageLog: var seq[seq[Rune]]) =

  let message = fmt"Restore successful {filename}"
  if settings.screenNotifications and settings.restoreScreenNotify:
    cmdWin.writeMessageOnCommandWindow(message, EditorColorPair.commandBar)
  if settings.logNotifications and settings.restoreLogNotify:
    messageLog.add(message.toRunes)

proc writeDeleteBackupError*(cmdWin: var Window) {.inline.} =
  const mess = "Error: Delete backup file failed"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
