import std/[strutils, terminal, unicode]
import ui, window, color, bufferstatus, independentutils

proc writeTab*(tabWin: var Window,
              start, tabWidth: int,
              filename: string,
              color: EditorColorPair) =

  let
    title = if filename == "": "New file" else: filename
    buffer = if filename.len < tabWidth:
               " " & title & " ".repeat(tabWidth - title.len)
             else: " " & (title).substr(0, tabWidth - 3) & "~"
  tabWin.write(0, start, buffer, color)

proc writeTabLineBuffer*(tabWin: var Window,
                         allBufStatus: seq[BufferStatus],
                         currentBufferIndex: int,
                         mainWindowNode: WindowNode,
                         isAllbuffer: bool) =

  let
    isAllBuffer = isAllbuffer
    defaultColor = EditorColorPair.tab
    currentTabColor = EditorColorPair.currentTab

  tabWin.erase

  if isAllBuffer:
    ## Display all buffer
    for index, bufStatus in allBufStatus:
      let
        color = if currentBufferIndex == index: currentTabColor
                else: defaultColor
        currentMode = bufStatus.mode
        prevMode = bufStatus.prevMode
        filename = if isFilerMode(currentMode, prevMode): $bufStatus.path
                   elif isHistoryManagerMode(currentMode, prevMode): "HISOTY"
                   elif isConfigMode(currentMode, prevMode): "CONFIG"
                   else: $bufStatus.path
        tabWidth = allBufStatus.len.calcTabWidth(terminalWidth())
      tabWin.writeTab(index * tabWidth, tabWidth, filename, color)
  else:
    ## Displays only the buffer currently displayed in the window
    let allBufferIndex =
      mainWindowNode.getAllBufferIndex
    for index, bufIndex in allBufferIndex:
      let
        color = if currentBufferIndex == bufIndex: currentTabColor
                else: defaultColor
        bufStatus = allBufStatus[bufIndex]
        currentMode = bufStatus.mode
        prevMode = bufStatus.prevMode
        filename = if isFilerMode(currentMode, prevMode): $bufStatus.path
                   elif isHistoryManagerMode(currentMode, prevMode): "HISOTY"
                   elif isConfigMode(currentMode, prevMode): "CONFIG"
                   else: $bufStatus.path
        numOfbuffer = mainWindowNode.getAllBufferIndex.len
        tabWidth = numOfbuffer.calcTabWidth(terminalWidth())
      tabWin.writeTab(index * tabWidth, tabWidth, filename, color)

  tabWin.refresh
