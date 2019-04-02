import terminal, math, strutils
import ui, editorstatus, unicodeext

proc calcTabWidth(numOfFile: int): int =
  let width = terminalWidth() / numOfFile
  result = int(ceil(width))

proc writeTab(tabWin: var Window, start, tabWidth: int, filename: seq[Rune], color: Colorpair) =
  let buffer = $filename & " ".repeat(tabWidth - filename.len)
  tabWin.write(0, start, buffer, color)

proc writeTabLine*(status: var EditorStatus) =
  let
    tabWidth = calcTabWidth(status.bufStatus.len)
    defaultColor = status.settings.tabLine.color
    currentTabColor = status.settings.tabLine.currentTabColor

  status.tabWindow.erase

  for i in 0 .. status.bufStatus.high:
    let color = if status.bufStatus[i].filename == status.filename: currentTabColor else: defaultColor
    writeTab(status.tabWindow, i * tabWidth, tabWidth, status.bufStatus[i].filename, color)

  status.tabWindow.refresh
