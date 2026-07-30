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

## Frontend-neutral pointer and scrolling input.
##
## Coordinates are cells in Moe's rendered grid. A GUI frontend should convert
## view coordinates before constructing these values. Positive
## `deltaPhysicalRows` scrolls toward later buffer lines; negative values scroll
## toward earlier lines.

import key_bindings/registry
export registry.KeyModifier

type
  GridRegion* = object
    ## Rectangular region in Moe's rendered cell grid.
    ## `rows` and `columns` are always non-negative for regions returned by Moe.
    row*: int
    column*: int
    rows*: int
    columns*: int

  PointerButton* = enum
    pbPrimary
    pbMiddle
    pbSecondary
    pbOther

  PointerAction* = enum
    paPress
    paRelease
    paMove
    paDrag

  PointerInput* = object
    row*: int
    column*: int
    button*: PointerButton
    action*: PointerAction
    clickCount*: Natural
    modifiers*: set[KeyModifier]

  ScrollInput* = object
    row*: int
    column*: int
    deltaPhysicalRows*: int
    modifiers*: set[KeyModifier]

  ScrollOutcome* = object
    ## Result of applying a semantic physical-line scroll.
    ##
    ## Movement fields are signed physical-line deltas (positive means later
    ## lines); grid-row conversion under line wrap is the consumer's job.
    ## `viewportPhysicalRowsMoved` is a pre-layout approximation that may be 0
    ## or short. It is a repaint hint, not an exact translation amount.
    handled*: bool
    region*: GridRegion
    requestedRows*: int
    appliedRows*: int
    viewportPhysicalRowsMoved*: int

func initGridRegion*(row, column, rows, columns: int): GridRegion =
  GridRegion(row: row, column: column, rows: max(rows, 0), columns: max(columns, 0))

func initPointerInput*(
    row, column: int,
    button = pbPrimary,
    action = paPress,
    clickCount: Natural = 1,
    modifiers: set[KeyModifier] = {},
): PointerInput =
  PointerInput(
    row: row,
    column: column,
    button: button,
    action: action,
    clickCount: clickCount,
    modifiers: modifiers,
  )

func initScrollInput*(
    row, column, deltaPhysicalRows: int, modifiers: set[KeyModifier] = {}
): ScrollInput =
  ScrollInput(
    row: row, column: column, deltaPhysicalRows: deltaPhysicalRows, modifiers: modifiers
  )
