import editorstatus
import gapbuffer

proc openFile*(filename: string): GapBuffer[string] =
  result = initGapBuffer[string]()
  let fs = open(filename, fmRead)
  while not fs.endOfFile: result.add(fs.readLine)
  fs.close()
