#ifndef MOE_VIEW_H
#define MOE_VIEW_H

#include <stdbool.h>
#include <ncurses.h>

typedef struct charArray charArray;
typedef struct gapBuffer gapBuffer;
typedef struct cursorPosition cursorPosition;

typedef struct editorView{
  int height, width, widthOfLineNum;
  charArray** lines;
  int* originalLine, *start, *length;
  bool isUpdated, *isCursorUpdated;
} editorView;

// width/heightでeditorViewを初期化し,バッファの0行0文字目からロードする.widthは画面幅ではなくeditorViewの1ラインの文字数である(従って行番号分の長さは考慮しなくてよい).
void initEditorView(editorView* view, gapBuffer* buffer, cursorPosition* cursor, int height, int width);
// topLineがeditorViewの一番上のラインとして表示されるようにバッファからeditorViewに対してリロード処理を行う.editorView全体を更新するため計算コストはやや高め.バッファの内容とeditorViewの内容を同期させる時やeditorView全体が全く異なるような内容になるような処理をした後等に使用することが想定されている.
void reloadEditorView(editorView *view, gapBuffer* buffer, int topLine);
// 指定されたwidth/heightでeditorViewを更新する.表示される部分はなるべくリサイズ前と同じになるようになっている.
void resizeEditorView(editorView* view, gapBuffer* buffer, int height, int width, int widthOfLineNum);
void freeEditorView(editorView* view);
// メインウィンドウの表示を1ライン上にずらす
void scrollUp(editorView* view, gapBuffer* buffer);
// メインウィンドウの表示を1ライン下にずらす
void scrollDown(editorView* view, gapBuffer* buffer);
int printLineNum(WINDOW *mainWindow, editorView* view, int line, int color,  int y);
void printLine(WINDOW *mainWindow, editorView* view, charArray* line, int y);
void printAllLines(WINDOW *mainWindow, editorView* view, gapBuffer *gb, int currentLine);
void updateView(editorView* view, WINDOW* mainWindow, gapBuffer* gb, int currentLine);
void seekCursor(editorView* view, gapBuffer* buffer, int currentLine, int positionInCurrentLine);

#endif
