import window, statusbar

type WorkSpace* = object
  mainWindowNode*: WindowNode
  currentMainWindowNode*: WindowNode
  numOfMainWindow*: int
  statusBar*: seq[StatusBar]

proc initWorkSpace*(): WorkSpace =
  var rootNode = initWindowNode()
  result.mainWindowNode = rootNode
  result.currentMainWindowNode = rootNode.child[0]
  result.numOfMainWindow = 1
  result.statusBar = @[initStatusBar()]
