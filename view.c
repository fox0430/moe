#include <stdlib.h>
#include "view.h"
#include "gapbuffer.h"
#include "chararray.h"
#include "cursor.h"
#include "mathutility.h"

// width/heightでeditorViewを初期化し,バッファの0行0文字目からロードする.widthは画面幅ではなくeditorViewの1ラインの文字数である(従って行番号分の長さは考慮しなくてよい).
void initEditorView(editorView* view, gapBuffer* buffer, cursorPosition* cursor, int height, int width){
  view->height = height;
  view->width = width;
  view->lines = (charArray**)malloc(sizeof(charArray*)*height);
  view->originalLine = (int*)malloc(sizeof(int)*height);
  view->start = (int*)malloc(sizeof(int)*height);
  view->length = (int*)malloc(sizeof(int)*height);
  view->widthOfLineNum = countDigit(buffer->size+1)+1;
  view->isUpdated = true;
  view->isCursorUpdated = &cursor->isUpdated;
  reloadEditorView(view, buffer, 0);
}

// topLineがeditorViewの一番上のラインとして表示されるようにバッファからeditorViewに対してリロード処理を行う.editorView全体を更新するため計算コストはやや高め.バッファの内容とeditorViewの内容を同期させる時やeditorView全体が全く異なるような内容になるような処理をした後等に使用することが想定されている.
void reloadEditorView(editorView *view, gapBuffer* buffer, int topLine){
  int height = view->height, width = view->width;  
  for(int y = 0; y < height; ++y){
    view->originalLine[y]= -1;
    view->lines[y] = (charArray*)malloc(sizeof(charArray));
    charArrayInit(view->lines[y]);
  }

  int lineNumber = topLine, start = 0;
  for(int y = 0; y < height; ++y){
    if(lineNumber >= buffer->size) break;
    if(gapBufferAt(buffer, lineNumber)->numOfChar == 0){
      view->originalLine[y] = lineNumber;
      view->start[y] = 0;
      view->length[y] = 0;
      ++lineNumber;
      continue;
    }
    view->originalLine[y] = lineNumber;
    view->start[y] = start;
    view->length[y] = width > gapBufferAt(buffer, lineNumber)->numOfChar - start ? gapBufferAt(buffer, lineNumber)->numOfChar - start : width;
    for(int x = 0; x < view->length[y]; ++x) charArrayPush(view->lines[y], gapBufferAt(buffer, lineNumber)->elements[x+view->start[y]]);

    start += width;
    if(start >= gapBufferAt(buffer, lineNumber)->numOfChar){
      ++lineNumber;
      start = 0;
    }
  } 
}

// 指定されたwidth/heightでeditorViewを更新する.表示される部分はなるべくリサイズ前と同じになるようになっている.
void resizeEditorView(editorView* view, gapBuffer* buffer, int height, int width){
  int topLine = view->originalLine[0];
  for(int y = 0; y < view->height; ++y) charArrayFree(view->lines[y]);
  view->lines = (charArray**)realloc(view->lines, sizeof(charArray*)*height);
  view->height = height;
  view->width = width;
  view->originalLine = (int*)realloc(view->originalLine, sizeof(int)*height);
  view->start = (int*)realloc(view->start, sizeof(int)*height);
  view->length = (int*)realloc(view->length, sizeof(int)*height);
  view->isUpdated = true;
  reloadEditorView(view, buffer, topLine);
}

void freeEditorView(editorView* view){
  for(int y = 0; y < view->height; ++y){
    charArrayFree(view->lines[y]);
  }
  free(view->lines);
  free(view->originalLine);
  free(view->start);
  free(view->length);
}

// メインウィンドウの表示を1ライン上にずらす
void scrollUp(editorView* view, gapBuffer* buffer){
  view->isUpdated  = true;

  int height = view->height;
  charArray* newLine = view->lines[height-1];
  while(newLine->numOfChar > 0) charArrayPop(newLine);
  
  for(int y = height-1; y >= 1; --y){
    view->lines[y] = view->lines[y-1];
    view->originalLine[y] = view->originalLine[y-1];
    view->start[y] = view->start[y-1];
    view->length[y] = view->length[y-1];
  }
  if(view->start[1] > 0){
    view->originalLine[0] = view->originalLine[1];
    view->start[0] = view->start[1]-view->width;
    view->length[0] = view->width;
  }else{
    view->originalLine[0] = view->originalLine[1]-1;
    view->start[0] = view->width*((gapBufferAt(buffer, view->originalLine[0])->numOfChar-1)/view->width);
    view->length[0] = gapBufferAt(buffer, view->originalLine[0])->numOfChar == 0 ? 0 : (gapBufferAt(buffer, view->originalLine[0])->numOfChar-1)%view->width+1;
  }

  for(int x = 0; x < view->length[0]; ++x) charArrayPush(newLine, gapBufferAt(buffer, view->originalLine[0])->elements[x+view->start[0]]);
  view->lines[0] = newLine;
}

// メインウィンドウの表示を1ライン下にずらす
void scrollDown(editorView* view, gapBuffer* buffer){
  view->isUpdated = true;

  charArray* newLine = view->lines[0];
  while(newLine->numOfChar > 0) charArrayPop(newLine);

  int height = view->height;
  for(int y = 0; y < height-1; ++y){
    view->lines[y] = view->lines[y+1];
    view->originalLine[y] = view->originalLine[y+1];
    view->start[y] = view->start[y+1];
    view->length[y] = view->length[y+1];
  }
  
  if(view->start[height-2]+view->length[height-2] == gapBufferAt(buffer, view->originalLine[height-2])->numOfChar){
    if(view->originalLine[height-2] == -1 || view->originalLine[height-2]+1 == buffer->size){
      view->originalLine[height-1] = -1;
      view->start[height-1] = 0;
      view->length[height-1] = 0;
    }else{
      view->originalLine[height-1] = view->originalLine[height-2]+1;
      view->start[height-1] = 0;
      view->length[height-1] = view->width > gapBufferAt(buffer, view->originalLine[height-1])->numOfChar ? gapBufferAt(buffer, view->originalLine[height-1])->numOfChar : view->width;
    }
  }else{
    view->originalLine[height-1] = view->originalLine[height-2];
    view->start[height-1] = view->start[height-2]+view->length[height-2];
    view->length[height-1] = view->width > gapBufferAt(buffer, view->originalLine[height-1])->numOfChar - view->start[height-1] ? gapBufferAt(buffer, view->originalLine[height-1])->numOfChar - view->start[height-1] : view->width;
  }
  for(int x = 0; x < view->length[height-1]; ++x) charArrayPush(newLine, gapBufferAt(buffer, view->originalLine[height-1])->elements[x+view->start[height-1]]);
  view->lines[height-1] = newLine;
}

int printLineNum(WINDOW *mainWindow, editorView* view, int line, int color,  int y){
  int width = view->widthOfLineNum;
  for(int j=0; j<width; j++) mvwprintw(mainWindow, y, j, " ");
  wattron(mainWindow, COLOR_PAIR(color));
  mvwprintw(mainWindow, y, 0, "%d", line + 1);
  return 0;
}

// print single line
void printLine(WINDOW *mainWindow, editorView* view, charArray* line, int y){
  wattron(mainWindow, COLOR_PAIR(6));
  mvwprintw(mainWindow, y, view->widthOfLineNum, "%s", line->elements);

}

void printAllLines(WINDOW *mainWindow, editorView* view, gapBuffer *gb, int currentLine){
  werase(mainWindow);
  view->widthOfLineNum = countDigit(gb->size+1)+1;
  for(int y = 0; y < view->height; ++y){
    if(view->originalLine[y] == -1){
      for(int x = 0; x < view->width; ++x) mvwprintw(mainWindow, y, x, " ");
      continue;
    }
    if(view->start[y] == 0) printLineNum(mainWindow, view, view->originalLine[y], view->originalLine[y] == currentLine ? 7 : 3, y);
    printLine(mainWindow, view, view->lines[y], y); 
  }
  wrefresh(mainWindow);
}

// カーソルがeditorView中に含まれるようになるまでscrollUp,scrollDownを利用してeditorViewの表示を移動させる.
void seekCursor(editorView* view, gapBuffer* buffer, int currentLine, int positionInCurrentLine){
  view->isUpdated = *view->isCursorUpdated = true;
  while(currentLine < view->originalLine[0] || (currentLine == view->originalLine[0] && view->length[0] > 0 && positionInCurrentLine < view->start[0])){
    scrollUp(view, buffer);
  }
 
  while((view->originalLine[view->height-1] != -1 && currentLine > view->originalLine[view->height-1]) || (currentLine == view->originalLine[view->height-1] && positionInCurrentLine >= view->start[view->height-1]+view->length[view->height-1])){
    scrollDown(view, buffer);
  }
}
