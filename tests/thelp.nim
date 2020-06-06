import unittest, strutils
import moepkg/[editorstatus, gapbuffer, unicodeext, movement, window, bufferstatus]

include moepkg/help

test "Display Help":
  var status = initEditorStatus()
  status.addNewBuffer("")

  status.resize(100, 100)
  status.update

  status.initHelpModeBuffer
  status.update

  let seqHelpSentences = helpSentences.splitlines

  check(status.bufStatus[0].filename == ru"help")

  for i in 0 ..< status.bufStatus[0].buffer.len:
    if i > 1: check(status.bufStatus[0].buffer[i] == seqHelpSentences[i - 1].toRunes)
