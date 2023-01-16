import std/[strformat, osproc, strutils]
import unicodeext, highlight, color

proc initDiffViewerBuffer*(sourceFilePath, backupFilePath: string): seq[Runes] =
  let cmdResult = execCmdEx(fmt"diff -u {sourceFilePath} {backupFilePath}")
  # The diff command return 2 on failure.
  if cmdResult.exitCode == 2:
    # TODO: Write the error message to the command window.
    return @[ru""]

  result = @[ru""]
  for line in cmdResult.output.splitLines:
    result.add line.toRunes

proc initDiffViewerHighlight*(buffer: seq[Runes]): Highlight =
  for i, line in buffer:
    let color =
      if line.len > 0 and line[0] == ru'+':
        EditorColorPair.addedLine
      elif line.len > 0 and line[0] == ru'-':
        EditorColorPair.deletedLine
      else:
        EditorColorPair.defaultChar

    result.colorSegments.add(ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: line.high,
      color: color))

proc initDiffViewerHighlight*(buffer: Runes): Highlight =
  return initDiffViewerHighlight(buffer.splitLines)
