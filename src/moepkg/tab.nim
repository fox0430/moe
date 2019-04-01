import terminal, math
import ui, editorstatus, unicodeext

proc setFileNames(bufStatus: seq[BufferStatus]): seq[seq[Rune]] =
  result = @[bufStatus[0].filename]
  for i in 1 .. bufStatus.high: result.add(bufStatus[i].filename)

proc calcTabWidth(filenames: seq[seq[Rune]]): int =
  let width = terminalWidth() / filenames.len
  result = int(ceil(width))

proc writeTabLine*(status: var EditorStatus) =
  let filenames = setFileNames(status.bufStatus)
  let tabWidth = calcTabWidth(filenames)

  for i in 0 .. filenames.high:
    status.tabWindow.write(0, i * tabWidth,  $filenames[i], brightWhiteDefault)
    status.tabWindow.write(0, tabWidth,  "|", brightWhiteDefault)
