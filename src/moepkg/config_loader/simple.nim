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

## Shared section-registry pieces for sections whose load/save is fully driven
## by the whole-config dispatch macros in `config_loader.nim`
## (`generateSectionLoaders` / `generateSectionSerializers`).
##
## Only the items the dispatch cannot derive on its own live here:
##   - `SimpleSectionNames`: the top-level section names, derived from
##     `EditorConfig`'s flat `{.cfgSection.}` fields, used for unknown-key
##     validation.
##   - the nested `[StartUp.*]` loaders, which are dispatched by hand under
##     their `[StartUp]` parent table rather than by `generateSectionLoaders`.
##
## Output formatting is value-stable for round-trips (parse -> compare-by-value;
## section/field order follows the struct declaration, not the legacy
## hand-written order), so the `saveConfigToToml round-trip completeness` test
## stays valid. Empty `seq[string]` fields serialize as `key = []`.

import pkg/parsetoml

import ../[config, config_macros]
import base

# Top-level TOML section names handled by the auto-generated loader dispatch.
# Derived from EditorConfig's {.cfgSection.} fields (excluding nested sections
# such as [StartUp.*]) so this list cannot drift from the actual sections.
const SimpleSectionNames* = generateSimpleSectionNames(EditorConfig)

# Nested [StartUp.*] loaders. These are the only per-section loaders that are
# still called by hand (from loadConfigFromToml, under the [StartUp] parent);
# every flat section is loaded by generateSectionLoaders.

proc loadStartUpFileOpenConfig*(
    table: TomlTableRef, config: var StartUpFileOpenConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, StartUpFileOpenConfig)

proc loadStartUpFileTreeConfig*(
    table: TomlTableRef, config: var StartUpFileTreeConfig, vr: var ValidationResult
) =
  generateConfigLoader(table, config, vr, StartUpFileTreeConfig)
