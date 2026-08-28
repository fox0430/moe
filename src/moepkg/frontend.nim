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

## Public convenience facade for embedding Moe in a non-terminal frontend.
##
## Hosts can construct and drive an `Editor`, translate native input through
## the frontend-neutral handlers, and read `FrontendStatus` without depending
## on Moe's terminal application entry point.
##
## Call `setFrontendGitStatusEnabled(true)` once when the host displays Git
## status, then call `tick` each frame before reading `frontendStatus`.

import
  config, editor, editor_frame, editor_display, editor_buffers, frontend_input, handler

export config.EditorConfig, config.newEditorConfig
export editor.Editor, editor.newEditor
export editor_frame.tick
export
  editor_display.FrontendStatus, editor_display.ActiveGitStatus,
  editor_display.frontendStatus, editor_display.frontendGitStatusEnabled,
  editor_display.setFrontendGitStatusEnabled
export
  editor_buffers.OpenBufferInfo, editor_buffers.activeWindowBuffers,
  editor_buffers.activateBuffer, editor_buffers.closeBuffer, editor_buffers.moveBuffer,
  editor_buffers.deleteCurrentBuffer
export
  frontend_input.GridRegion, frontend_input.PointerButton, frontend_input.PointerAction,
  frontend_input.PointerInput, frontend_input.ScrollInput, frontend_input.ScrollOutcome
export handler.handleTextInput, handler.handleEvent
