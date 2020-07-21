import strutils, os, terminal
import ui, window, color, bufferstatus, workspace, independentutils, unicodeext

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
                  workspace: WorkSpace,
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
        filename = if (currentMode == Mode.filer) or
                      (prevMode == Mode.filer and
                      currentMode == Mode.ex): getCurrentDir()
                   else: $bufStatus.path
        tabWidth = allBufStatus.len.calcTabWidth(terminalWidth())
      tabWin.writeTab(index * tabWidth, tabWidth, filename, color)
  else:
    ## Displays only the buffer currently displayed in the window
    let allBufferIndex =
      workSpace.mainWindowNode.getAllBufferIndex
    for index, bufIndex in allBufferIndex:
      let
        color = if currentBufferIndex == bufIndex: currentTabColor
                else: defaultColor
        bufStatus = allBufStatus[bufIndex]
        currentMode = bufStatus.mode
        prevMode = bufStatus.prevMode
        filename = if (currentMode == Mode.filer) or
                      (prevMode == Mode.filer and
                      currentMode == Mode.ex): getCurrentDir()
                   else: $bufStatus.path
        numOfbuffer =
          workSpace.mainWindowNode.getAllBufferIndex.len
        tabWidth = numOfbuffer.calcTabWidth(terminalWidth())
      tabWin.writeTab(index * tabWidth, tabWidth, filename, color)

  tabWin.refresh

proc writeTabLineWorkSpace*(tabWin: var Window,
                            workSpaceLen: int,
                            currentWorkSpaceIndex: int) =

  tabWin.erase

  let
    defaultColor = EditorColorPair.tab
    currentTabColor = EditorColorPair.currentTab

  for i in 0 ..< workSpaceLen:
    let
      color = if i == currentWorkSpaceIndex: currentTabColor else: defaultColor
      tabWidth = workSpaceLen.calcTabWidth(terminalWidth())
      buffer = "WorkSpace: " & $i
    tabWin.writeTab(i * tabWidth, tabWidth, buffer, color)

  tabWin.refresh
