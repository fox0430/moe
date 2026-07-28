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

## Push the editor's `config.highlight` settings (reserved words and the
## per-line tokenization cap) into a buffer's syntax-highlight state. This is
## about the editor's OWN config, not `.editorconfig` files — those live in
## `editorconfig_helper`.

import config
import buffer/[core, highlight]

proc applyHighlightCap*(buffer: TextBuffer, config: EditorConfig) =
  ## Seed the per-line tokenization cap from config. Must run BEFORE `loadFile`,
  ## which reads `maxHighlightLineLength` to cap the first chunk. Applying it
  ## afterwards would nil the freshly-seeded progressive-load cache and force a
  ## full synchronous reparse on open — the stall the cap exists to prevent.
  buffer.setMaxHighlightLineLength(config.highlight.maxHighlightLineLength)

proc applyHighlightConfig*(buffer: TextBuffer, config: EditorConfig) =
  ## Apply config-derived highlight settings (reserved words + per-line cap) to
  ## a buffer, funnelling both through one call so they cannot drift.
  ##
  ## Reserved words must be applied AFTER `loadFile` (it clears
  ## `highlightNeedsUpdate`, which this sets). The cap needs the opposite order
  ## (see `applyHighlightCap`), so content-load sites seed it before `loadFile`
  ## and the cap update here is a no-op. Empty buffers have no content, so order
  ## is moot for them.
  buffer.setReservedWords(toReservedWords(config.highlight.reservedWord))
  buffer.applyHighlightCap(config)
