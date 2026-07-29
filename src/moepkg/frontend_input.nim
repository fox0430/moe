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
## view coordinates before constructing these values. Positive `deltaRows`
## scrolls toward later buffer rows; negative values scroll toward earlier rows.

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
    deltaRows*: int
    modifiers*: set[KeyModifier]

  ScrollOutcome* = object
    ## Result of applying a semantic row scroll.
    ##
    ## A GUI bridge can translate `region` when `viewportRowsMoved != 0`, while
    ## repainting ordinary cell changes (such as cursor movement) without moving
    ## the surrounding tab/status rows. Movement fields are signed: positive is
    ## toward later buffer rows.
    handled*: bool
    region*: GridRegion
    requestedRows*: int
    appliedRows*: int
    viewportRowsMoved*: int

func initGridRegion*(row, column, rows, columns: int): GridRegion =
  GridRegion(
    row: row,
    column: column,
    rows: max(rows, 0),
    columns: max(columns, 0),
  )

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
    row, column, deltaRows: int, modifiers: set[KeyModifier] = {}
): ScrollInput =
  ScrollInput(
    row: row, column: column, deltaRows: deltaRows, modifiers: modifiers
  )
