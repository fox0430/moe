import editorstatus
import gapbuffer, unicodeext

proc openFile*(filename: seq[Rune]): GapBuffer[seq[Rune]] =
  result = initGapBuffer[seq[Rune]]()
  let fs = open($filename)
  while not fs.endOfFile: result.add(fs.readLine.toRunes)
  fs.close()

proc newFile*(): GapBuffer[seq[Rune]] =
  result = initGapBuffer[seq[Rune]]()
  result.add(ru"")

proc saveFile*(filename: seq[Rune], buffer: GapBuffer[seq[Rune]]) =
  let fs = open($filename, fmWrite)
  for line in 0 .. buffer.high: fs.writeLine($buffer[line])
  fs.close()
