#ifndef  MOE_MOE_H
#define MOE_MOE_H

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
  char filename[256];
  int   currentLine,
        positionInCurrentLine,
        expandedPosition,
        mode,
        cmdLoop,
        numOfChange,
        debugMode;
} editorStatus;

#endif
