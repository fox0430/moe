import window, statusline

type WorkSpace* = object
  mainWindowNode*: WindowNode
  currentMainWindowNode*: WindowNode
  numOfMainWindow*: int
  statusLine*: seq[StatusLine]

proc initWorkSpace*(): WorkSpace =
  var rootNode = initWindowNode()
  result.mainWindowNode = rootNode
  result.currentMainWindowNode = rootNode.child[0]
  result.numOfMainWindow = 1
  result.statusLine = @[initStatusLine()]
