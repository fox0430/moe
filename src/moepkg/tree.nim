import ui, editorstatus

# Split window tree
type SplitWindowList* = object
  currentVPosition: int
  currentHPossition: int
  win: seq[seq[MainWindowInfo]]

proc initSplitWindowList*(): SplitWindowList = SplitWindowList()

proc horizontalSplitWin*(status: var Editorstatus, splitWinList: SplitWindowList) =
  let new Wind(MainWindowInfo(window: initWindow(terminalHeight() - useTab - 1, terminalWidth(), useTab, 0), height: 100, width: 100, bufferIndex: 0))
  splitWinList.win[splitWinList.currentVPosition].add(newWin)
