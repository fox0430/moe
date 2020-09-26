import ui, unicodeext, color

type CommandLine* = object
    buffer: seq[Rune]
    color: EditorColorPair

proc initCommandLine*(): CommandLine {.inline.} =
  result.color = EditorColorPair.defaultChar

proc updateCommandBuffer*(commndLine: var CommandLine,
                          buffer: seq[Rune],
                          color: EditorColorPair) =

  commndLine.buffer = buffer
  commndLine.color = color

proc updateCommandLineBuffer*(commndLine: var CommandLine,
                          buffer: string,
                          color: EditorColorPair) {.inline.} =
  commndLine.updateCommandBuffer(ru buffer, color)

proc updateCommandLineBuffer*(commndLine: var CommandLine,
                          buffer: string) {.inline.} =
  commndLine.updateCommandBuffer(ru buffer, EditorColorPair.commandBar)

proc updateCommandLineBuffer*(commndLine: var CommandLine,
                          buffer: seq[Rune]) {.inline.} =
  commndLine.updateCommandBuffer(buffer, EditorColorPair.commandBar)

proc updateCommandLineView*(commndLine: CommandLine, cmdWin: var Window) =
  cmdWin.erase
  cmdWin.write(0, 0, commndLine.buffer, commndLine.color)
  cmdWin.refresh

proc clear*(commndLine: var CommandLine) {.inline.} = commndLine.buffer = ru""
