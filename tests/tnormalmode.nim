import unittest, osproc
import moepkg/[editorstatus, gapbuffer, normalmode, unicodeext, editor]

test "Delete current character":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.currentColumn = 1
  status.bufStatus[0].deleteCurrentCharacter(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.settings.autoDeleteParen)
  check(status.bufStatus[0].buffer[0] == ru"ac")

test "Add indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
  const tabStop = 2
  status.bufStatus[0].addIndent(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, tabStop)
  check(status.bufStatus[0].buffer[0] == ru"  abc")

test "Delete indent":
  var status = initEditorStatus()
  status.addNewBuffer("")
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  const tabStop = 2
  status.bufStatus[0].deleteIndent(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, tabStop)
  check(status.bufStatus[0].buffer[0] == ru"abc")

test "Send to clipboard 1":
  const registers = Registers(yankedLines: @[], yankedStr: ru"Clipboard test")

  const platform = Platform.linux

  registers.sendToClipboad(platform)
  let (output, exitCode) = execCmdEx("xclip -o")

  check(exitCode == 0 and output[0 .. output.high - 1] == "Clipboard test")

test "Send to clipboard 2":
  const registers = Registers(yankedLines: @[], yankedStr: ru"`Clipboard test`")

  const platform = Platform.linux

  registers.sendToClipboad(platform)
  let (output, exitCode) = execCmdEx("xclip -o")

  check(exitCode == 0 and output[0 .. output.high - 1] == "`Clipboard test`")

test "Send to clipboard 3":
  const registers = Registers(yankedLines: @[], yankedStr: ru"`````")

  const platform = Platform.linux

  registers.sendToClipboad(platform)
  let (output, exitCode) = execCmdEx("xclip -o")

  check(exitCode == 0 and output[0 .. output.high - 1] == "`````")

test "Send to clipboard 4":
  const registers = Registers(yankedLines: @[], yankedStr: ru"$Clipboard test")

  const platform = Platform.linux

  registers.sendToClipboad(platform)
  let (output, exitCode) = execCmdEx("xclip -o")

  check(exitCode == 0 and output[0 .. output.high - 1] == "$Clipboard test")
