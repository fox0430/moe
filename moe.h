#ifndef  MOE_MOE_H
#define MOE_MOE_H

#include <limits.h>
#include "gapbuffer.h"
#include "chararray.h"
#include "view.h"
#include "cursor.h"

typedef struct registers{
  gapBuffer *yankedLine;
  charArray *yankedStr;
  int numOfYankedLines,
      numOfYankedStr;
} registers;

typedef struct editorSetting{
  int autoCloseParen,
      autoIndent,
      tabStop;
} editorSetting;

typedef struct editorStatus{
  editorSetting setting;
  registers rgst;
  editorView view;
  cursorPosition cursor;
  char  filename[NAME_MAX],
        currentDir[PATH_MAX];
  int   currentLine,
        positionInCurrentLine,
        expandedPosition,
        mode,
        cmdLoop,
        numOfChange,
        debugMode;
} editorStatus;

void winResizeEvent(WINDOW **win, gapBuffer *gb, editorStatus *status);
void editorStatusInit(editorStatus* status);
int insNewLine(gapBuffer *gb, editorStatus *status, int position);
int openFile(gapBuffer *gb, editorStatus *status);
int exMode(WINDOW **win, gapBuffer *gb, editorStatus *status);
void printStatBarInit(WINDOW *win, gapBuffer *gb, editorStatus *status);
int printStatBar(WINDOW *win, gapBuffer *gb, editorStatus *status);
void printNoWriteError(WINDOW *win);

#endif
