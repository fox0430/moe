import posix
import os
import system
import terminal
import streams
import moepkg/ui
import moepkg/view
import moepkg/gapbuffer

type EditorSettings = object
  autoCloseParen: bool
  autoIndent:     bool 
  tabStop:        int

type EditorStatus = object
  view:                   EditorView
  setting:                EditorSettings
  filename:               string
  currentDir:             string
  termHeight:             int
  termWidth:              int
  currentLine:            int
  currentColumn:          int
  expandePosition:        int
  mode:                   int
  cmdLoop:                int
  numOfChange:            int
  debugMode:              int

proc initEditorSettings(): EditorSettings = discard

proc initEditorStatus(): EditorStatus =
  result.termHeight = terminalHeight()
  result.termWidth = terminalWidth()
  result.filename = "No name"
  result.currentDir = getCurrentDir()
  result.setting = initEditorSettings()

proc newFile(): EditorStatus =
  result.currentLine = 0

proc openFile(filename: string): GapBuffer[string] =
  var result = initGapBuffer[string]()
  var fs = newFileStream(filename, fmRead)
  var line = ""
  if not isNil(fs):
    while fs.readLine(line):
      result.add(line)
    fs.close()
    return result
  
if isMainModule:
  var status = initEditorStatus()

  startUi()
  exitUi()

  if paramCount() == 0:
    var gb = initGapBuffer[string]()
    status = newFile()
    quit()
  else:
    status.filename = os.commandLineParams()[0]
    var gb = openFile(status.filename)
    quit()
