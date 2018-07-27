import editorstatus
import gapbuffer

proc openFile*(filename: string): GapBuffer[string] =
  result = initGapBuffer[string]()
  let fs = open(filename)
  while not fs.endOfFile: result.add(fs.readLine)
  fs.close()

proc newFile*(): GapBuffer[string] =
  result = initGapBuffer[string]()
  result.add("")

proc saveFile*(filename: string, buffer: GapBuffer[string]) =
  let fs = open(filename, fmWrite)
  for line in 0 .. buffer.high: fs.writeLine(buffer[line])
  fs.close()
