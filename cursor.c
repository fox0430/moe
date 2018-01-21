#include "cursor.h"


// カーソルが表示位置を計算/更新する.この関数が呼ばれるとき現在のeditorView中にカーソルの正しい表示位置が含まれていることが期待される.
void updateCursorPosition(cursorPosition* cursor, editorView* view, int currentLine, int positionInCurrentLine){
  for(int y = 0; y < view->height; ++y){
    if(currentLine == view->originalLine[y]){
      if(view->start[y] <= positionInCurrentLine && positionInCurrentLine < view->start[y]+view->length[y]){
        cursor->y = y;
        cursor->x = positionInCurrentLine-view->start[y];
        break;
      }else if ((y == view->height-1 || view->originalLine[y] != view->originalLine[y+1]) && view->start[y]+view->length[y] == positionInCurrentLine){
        cursor->y = y;
        cursor->x = positionInCurrentLine-view->start[y];
        if(cursor->x == view->width){
            ++cursor->y;
            cursor->x = 0;
        }
        break;
      }
    }
  }
}
