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

import types, buffer/core, motion

proc buffer*(mc: MotionController): core.TextBuffer =
  ## Buffer the motion controller currently targets.
  mc.executor.buffer

proc setBuffer*(mc: MotionController, b: core.TextBuffer) =
  ## Point the motion controller at `b`.
  mc.executor.buffer = b

proc bindToWindow*(mc: MotionController, win: EditorWindow) =
  ## Bind the motion controller to `win`'s buffer/viewport.
  ## Single place that re-aliases the per-window state the controller caches,
  ## so window switch / split / close / resize only update one method.
  mc.setBuffer(win.buffer)
  mc.viewportManager.viewport = win.viewport
  mc.viewportManager.wrapCountCache = win.wrapCountCache
