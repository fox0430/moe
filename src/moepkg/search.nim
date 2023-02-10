#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

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
