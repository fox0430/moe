import editorstatus, searchutils, unicodeext, bufferstatus

proc execSearchCommand*(status: var EditorStatus, keyword: Runes) =
  status.searchHistory[^1] = keyword

  if isSearchForwardMode(currentBufStatus.mode):
    currentBufStatus.jumpToSearchForwardResults(
      currentMainWindowNode,
      keyword,
      status.settings.ignorecase,
      status.settings.smartcase)
  else:
    currentBufStatus.jumpToSearchBackwordResults(
      currentMainWindowNode,
      keyword,
      status.settings.ignorecase,
      status.settings.smartcase)
