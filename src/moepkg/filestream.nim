import streams
import editorstatus
import gapbuffer

proc newFile*(): EditorStatus =
  result.currentLine = 0

proc openFile*(filename: string): GapBuffer[string] =
  var result = initGapBuffer[string]()
  var fs = newFileStream(filename, fmRead)
  var line = ""
  if not isNil(fs):
    while fs.readLine(line):
      result.add(line)
    fs.close()
    return result
