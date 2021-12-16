import std/terminal
import ui, unicodeext, color

type CommandLine* = object
    buffer: seq[Rune]
    color: EditorColorPair
    window*: Window

proc initCommandLine*(): CommandLine {.inline.} =
  result.color = EditorColorPair.defaultChar
  # Init command line window
  const
    t = 0
    l = 0
    color = EditorColorPair.defaultChar
  let
    w = terminalWidth()
    h = terminalHeight() - 1
  result.window = initWindow(h, w, t, l, color)
  result.window.setTimeout()

proc resize*(commndLine: var CommandLine, y, x, h, w: int) {.inline.} =
  commndLine.window.resize(h, w, y, x)

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

proc updateCommandLineView*(commndLine: var CommandLine) =
  commndLine.window.erase
  commndLine.window.write(0, 0, commndLine.buffer, commndLine.color)
  commndLine.window.refresh

proc erase*(commndLine: var CommandLine) =
  commndLine.buffer = ru""
  commndLine.window.erase
  commndLine.window.refresh

proc getKey*(commndLine: var CommandLine): Rune {.inline.} =
  commndLine.window.getkey
