import editorstatus
import gapbuffer

proc openFile*(filename: string): GapBuffer[string] =
  result = initGapBuffer[string]()
  let fs = open(filename, fmRead)
  while not fs.endOfFile: result.add(fs.readLine)
  fs.close()

proc saveFile*(filename: string, buffer: GapBuffer[string]) =
  let fs = open("test", fmWrite)
  for line in 0..len(buffer) - 1:
    fs.writeLine buffer[line]
  fs.close()
