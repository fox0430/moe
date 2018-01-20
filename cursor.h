#ifndef MOE_CURSOR_H
#define MOE_CURSOR_H

#include <stdbool.h>
#include "view.h"

typedef struct cursorPosition{
  int y,x;
  bool isUpdated;
} cursorPosition;

// カーソルが表示位置を計算/更新する.この関数が呼ばれるとき現在のeditorView中にカーソルの正しい表示位置が含まれていることが期待される.
void updateCursorPosition(cursorPosition* cursor, editorView* view, int currentLine, int positionInCurrentLine);

#endif
