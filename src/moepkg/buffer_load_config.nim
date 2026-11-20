#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## The settings a buffer filled from a file takes around the load, the same
## for every load, so a file looks the same however it was read.

import config, editorconfig_helper, highlight_config
import buffer/core

template loadWithConfig*(buffer: TextBuffer, config: EditorConfig, load: untyped) =
  ## Run `load`, which fills `buffer` from a file, with the highlight cap set
  ## before it (the first chunk reads it) and `.editorconfig` and the reserved
  ## words after it (the load resets what they set). A `return` in `load`
  ## skips what comes after.
  buffer.applyHighlightCap(config)
  load
  applyEditorConfigToBuffer(buffer, config)
  applyHighlightConfig(buffer, config)
