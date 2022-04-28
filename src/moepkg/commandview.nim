import std/[terminal, os, times]
import  unicodeext, commandviewutils, ui, color

proc suggestCommandLine*(commandLine: var CommandLine,
                        key: var Rune) =

  let
    suggestType = getSuggestType(commandLine.buffer)
    suggestlist = commandLine.getSuggestList(suggestType)

  var
    suggestIndex = 0
    # Pop up window initial size/position
    h = 1
    w = 1
    x = 0
    y = terminalHeight() - 1

  let command = if commandLine.buffer.len > 0:
                  (splitWhitespace(commandLine.buffer))[0]
                else: ru""

  if isSuggestTypeFilePath(suggestType):
    x = calcXWhenSuggestPath(commandLine.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    x = command.len + 1

  # TODO: Enable popUpWindow
  #var popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  template updateExModeViewStatus() =
    if isSuggestTypeFilePath(suggestType):
      commandLine.buffer = command & ru" "
      commandLine.currentPosition = command.len + commandLine.prompt.len
      commandLine.cursorX = commandLine.currentPosition
    else:
      commandLine.buffer = ru""
      commandLine.currentPosition = 0
      commandLine.cursorX = 0

  # TODO: I don't know why yet,
  #       but there is a bug which is related to scrolling of the pup-up window.

  while (isTabKey(key) or isShiftTab(key)) and suggestlist.len > 1:
    updateExModeViewStatus()

    if isTabKey(key) and suggestIndex < suggestlist.high: inc(suggestIndex)
    elif isShiftTab(key) and suggestIndex > 0: dec(suggestIndex)
    elif isShiftTab(key) and suggestIndex == 0: suggestIndex = suggestlist.high
    else: suggestIndex = 0

    # TODO: Enable popupwindow
    #if status.settings.popUpWindowInExmode:
    #  let
    #    currentLine = if suggestIndex == 0: -1 else: suggestIndex - 1
    #    displayBuffer = initDisplayBuffer(suggestlist, suggestType)
    #  # Pop up window size
    #  var (h, w) = displayBuffer.calcPopUpWindowSize

    #  popUpWindow.writePopUpWindow(h, w, y, x,
    #                               terminalHeight(), terminalWidth(),
    #                               currentLine,
    #                               displayBuffer)

    if isSuggestTypeExCommandOption(suggestType):
      commandLine.insertCommandBuffer(command & ru' ')

    commandLine.insertCommandBuffer(suggestlist[suggestIndex])
    commandLine.cursorX.inc

    commandLine.writeExModeView(EditorColorPair.commandBar)

    key = NONE_KEY
    while key == NONE_KEY:
      key = getKey()

    commandLine.cursorX = commandLine.currentPosition + 1

  # TODO: Enable cursor
  #status.commandLine.window.moveCursor(commandLine.cursorY, commandLine.cursorX)
  # TODO: Enable popUpWindow
  #if status.settings.popUpWindowInExmode: status.deletePopUpWindow
