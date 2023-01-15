import std/options
import ui, color, unicodeext

# TODO: Add PopUpWindow type

proc writePopUpWindow*(
  popUpWindow: var Window,
  h, w, y, x: int,
  currentLine: Option[int],
  buffer: seq[Runes]) =

    # TODO: Probably, the parameter `y` means the bottom of the window,
    #       but it should change to the top of the window for consistency.

    popUpWindow.erase

    # Pop up window position
    let
      absY = y.clamp(0, getTerminalHeight() - 1 - h)
      absX = x.clamp(0, getTerminalWidth() - w)

    popUpWindow.resize(h, w, absY, absX)

    let startLine =
      if currentLine.isSome and currentLine.get - h >= 0:
        currentLine.get - h + 1
      else:
        0

    for i in 0 ..< h:
      if currentLine.isSome and i + startLine == currentLine.get:
        let color = EditorColorPair.popUpWinCurrentLine
        popUpWindow.write(i, 1, buffer[i + startLine], color, false)
      else:
        let color = EditorColorPair.popUpWindow
        popUpWindow.write(i, 1, buffer[i + startLine], color, false)

    popUpWindow.refresh

# Delete the popup window.
# Need `status.update` after delete it.
proc delete*(popUpWindow: var Window) =
  # TODO: Use Option type
  if popUpWindow != nil:
    popUpWindow.deleteWindow
