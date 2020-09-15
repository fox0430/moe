import sequtils, tables

type
  CommandKind = enum
    insert,
    delete,
    assign

  Command*[T] = ref CommandObj[T]
  CommandObj*[T] = object
    case kind*: CommandKind
    of insert:
      insertElement*: T
      insertPosition*: int
    of delete:
      deleteElement*: T
      deletePosition*: int
    of assign:
      oldElement, newElement*: T
      assignPosition*: int

proc newInsertCommand*[T](element: T, position: int): Command[T] {.inline.} =
  Command[T](kind: insert, insertElement: element, insertPosition: position)

proc newDeleteCommand*[T](element: T, position: int): Command[T] {.inline.} =
  Command[T](kind: delete, deleteElement: element, deletePosition: position)

proc newAssignCommand*[T](oldElement, newElement: T, position: int): Command[T] {.inline.} =
  Command[T](kind: assign,
             oldElement: oldElement,
             newElement: newElement,
             assignPosition: position)

proc doInsert[T, U](command: Command[T],
                    buffer: var U,
                    pushToStack: bool = true) {.inline.} =

  doAssert(command.kind == CommandKind.insert)
  buffer.insert(command.insertElement, command.insertPosition, pushToStack)

proc doDelete[T, U](command: Command[T],
                    buffer: var U,
                    pushToStack: bool = true) {.inline.} =

  doAssert(command.kind == CommandKind.delete)
  buffer.delete(command.deletePosition, pushToStack)

proc doAssign[T, U](command: Command[T],
                    buffer: var U,
                    pushToStack: bool = true) {.inline.} =

  doAssert(command.kind == CommandKind.assign)
  buffer.assign(command.newElement, command.assignPosition, pushToStack)

proc doCommand[T, U](command: Command[T],
                     buffer: var U,
                     pushToStack: bool = true) =

  case command.kind:
  of insert: doInsert(command, buffer, pushToStack)
  of delete: doDelete(command, buffer, pushToStack)
  of assign: doAssign(command, buffer, pushToStack)

proc inverseOfInsert[T](command: Command[T]): Command[T] {.inline.} =
  doAssert(command.kind == CommandKind.insert)
  return newDeleteCommand[T](command.insertElement, command.insertPosition)

proc inverseOfDelete[T](command: Command[T]): Command[T] {.inline.} =
  doAssert(command.kind == CommandKind.delete)
  return newInsertCommand[T](command.deleteElement, command.deletePosition)

proc inverseOfAssign[T](command: Command[T]): Command[T] {.inline.} =
  doAssert(command.kind == CommandKind.assign)
  return newAssignCommand[T](command.newElement,
                             command.oldElement,
                             command.assignPosition)

proc inverseCommand[T](command: Command[T]): Command[T] =
  case command.kind:
  of delete: inverseOfDelete(command)
  of insert: inverseOfInsert(command)
  of assign: inverseOfAssign(command)

type
  CommandSuit[T] = object
    commands: seq[Command[T]]
    locked: bool
    id: int

  UndoRedoStack*[T] = object
    undoSuits, redoSuits: seq[CommandSuit[T]]
    currentSuit: CommandSuit[T]

var nextSuitId = 1

proc initCommandSuit[T](): CommandSuit[T] {.inline.} =
  result = CommandSuit[T](commands: @[], locked: false, id: nextSuitId)
  inc(nextSuitId)

proc len[T](commandSuit: CommandSuit[T]): int {.inline.} = commandSuit.commands.len

proc add[T](commandSuit: var CommandSuit[T], x: Command[T]) {.inline.} =
  commandSuit.commands.add(x)

proc `[]`[T](commandSuit: CommandSuit[T], i: Natural): Command[T] {.inline.} =
  commandSuit.commands[i]

proc `[]`[T](commandSuit: CommandSuit[T], i: BackwardsIndex): Command[T] {.inline.} =
  commandSuit.commands[i]

proc initUndoRedoStack*[T](): UndoRedoStack[T] {.inline.} =
  result.currentSuit = initCommandSuit[T]()

proc lockCurrentSuit*[T](undoRedoStack: var UndoRedoStack[T]) =
  undoRedoStack.currentSuit.locked = true
  undoRedoStack.undoSuits.add(undoRedoStack.currentSuit)
  undoRedoStack.currentSuit = initCommandSuit[T]()

proc lastSuitId*[T](undoRedoStack: UndoRedoStack[T]): int =
  ## Return the id that was applied last.
  if undoRedoStack.undoSuits.len == 0: return 0
  if undoRedoStack.currentSuit.len > 0: undoRedoStack.currentSuit.id
  else: undoRedoStack.undoSuits[^1].id

proc beginNewSuitIfNeeded*[T](undoRedoStack: var UndoRedoStack[T]) {.inline.} =
  if undoRedoStack.currentSuit.len > 0: undoRedoStack.lockCurrentSuit

proc push*[T](undoRedoStack: var UndoRedoStack[T], command: Command[T]) =
  if  undoRedoStack.redoSuits.len > 0: undoRedoStack.redoSuits = @[]

  doAssert(not undoRedoStack.currentSuit.locked)
  undoRedoStack.currentSuit.add(command)

proc undo*[T, U](undoRedoStack: var UndoRedoStack[T], buffer: var U) =
  doAssert(undoRedoStack.undoSuits.len > 0)

  for i in 1..undoRedoStack.undoSuits[undoRedoStack.undoSuits.high].len:
    doCommand[T, U](inverseCommand[T](
      undoRedoStack.undoSuits[undoRedoStack.undoSuits.high][^i]),
      buffer,
      false)

  undoRedoStack.redoSuits.add(undoRedoStack.undoSuits.pop)

proc redo*[T, U](undoRedoStack: var UndoRedoStack[T], buffer: var U) =
  doAssert(undoRedoStack.redoSuits.len > 0)

  for i in 0..<undoRedoStack.redoSuits[undoRedoStack.redoSuits.high].len:
    let command = undoRedoStack.redoSuits[undoRedoStack.redoSuits.high][i]
    doCommand[T, U](command, buffer, false)

  undoRedoStack.undoSuits.add(undoRedoStack.redoSuits.pop)

proc canUndo*[T](undoRedoStack: UndoRedoStack[T]): bool {.inline.} =
  return undoRedoStack.undoSuits.len > 0

proc canRedo*[T](undoRedoStack: UndoRedoStack[T]): bool {.inline.} =
  return undoRedoStack.redoSuits.len > 0
