import strformat, os
import ui, color, unicodeext

proc writeMessageOnCommandWindow*(cmdWin: var Window,
                                 message: string,
                                 color: EditorColorPair) =

  cmdWin.erase
  cmdWin.write(0, 0, message, color)
  cmdWin.refresh

proc writeNoWriteError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: No changes since last write"
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

proc writeCreateDirError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: Can not create directory"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeMessageDeletedFile*(cmdWin: var Window,
                              filename: string,
                              messageLog: var seq[seq[Rune]]) =
                              
  let mess = "Deleted: " & filename
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeNoFileNameError*(cmdWin: var Window, messageLog: var seq[seq[Rune]]) =
  let mess = "Error: No file name"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
  messageLog.add(mess.toRunes)

proc writeMessageYankedLine*(cmdWin: var Window,
                             numOfLine: int,
                             messageLog: var seq[seq[Rune]]) =
                             
  let mess = fmt"{numOfLine} line(s) yanked"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeMessageYankedCharactor*(cmdWin: var Window,
                                  numOfChar: int,
                                  messageLog: var seq[seq[Rune]]) =
                                  
  let mess = fmt"{numOfChar} character(s) yanked"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeMessageAutoSave*(cmdWin: var Window,
                           filename: seq[Rune],
                           messageLog: var seq[seq[Rune]]) =
                           
  let mess = fmt"Auto saved {filename}"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeMessageBuildOnSave*(cmdWin: var Window,
                              messageLog: var seq[seq[Rune]]) =
                              
  const mess = "Build on save..."
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeMessageSuccessBuildOnSave*(cmdWin: var Window,
                                     messageLog: var seq[seq[Rune]]) =
                                     
  const mess = "Build successful, file saved"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeMessageFailedBuildOnSave*(cmdWin: var Window,
                                    messageLog: var seq[seq[Rune]]) =
                                    
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
                           messageLog: var seq[seq[Rune]]) =
                           
  let mess = fmt"Saved {filename}"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
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
                                  messageLog: var seq[seq[Rune]]) =

  const mess = "Start automatic backup..."
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)
  messageLog.add(mess.toRunes)

proc writeAutoBackupSuccessMessage*(cmdWin: var Window,
                                    message: string) =

  cmdWin.writeMessageOnCommandWindow(message, EditorColorPair.commandBar)

proc writeRunQuickRunMessage*(cmdWin: var Window) =
  const mess = "Quick run..."
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.commandBar)

proc writeRunQuickRunTimeoutMessage*(cmdWin: var Window) =
  const mess = "Quick run timeout"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)

proc writeRunQuickRunFailedMessage*(cmdWin: var Window) =
  const mess = "Quick run failed"
  cmdWin.writeMessageOnCommandWindow(mess, EditorColorPair.errorMessage)
