import terminal, math, strutils
import ui, editorstatus, unicodeext

proc calcTabWidth(numOfBuffer: int): int =
  let width = terminalWidth() / numOfBuffer
  result = int(ceil(width))

proc writeTab(tabWin: var Window, start, tabWidth: int, filename: seq[Rune], color: Colorpair) =
  let title = if filename == ru"": "New file" else: $filename
  let buffer = if filename.len < tabWidth: " " & title & " ".repeat(tabWidth - title.len) else: " " & (title).substr(0, tabWidth - 3) & "~"
  tabWin.write(0, start, buffer, color)

proc writeTabLine*(status: var EditorStatus) =
  let
    tabWidth = calcTabWidth(status.displayBuffer.len)
    defaultColor = status.settings.editorColor.tab
    currentTabColor = status.settings.editorColor.currentTab

  status.tabWindow.erase

  for i in 0 ..< status.displayBuffer.len:
    let color = if status.currentMainWindow == i: currentTabColor else: defaultColor
    status.tabWindow.writeTab(i * tabWidth, tabWidth, status.bufStatus[status.displayBuffer[i]].filename, color)

  status.tabWindow.refresh
