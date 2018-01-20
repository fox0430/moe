#ifndef  MOE_MOE__H
#define MOE_MOE_H

#include "gapbuffer.h"
#include "chararray.h"
#include "view.h"

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

typedef struct cursorPosition{
  int y,x;
  bool isUpdated;
} cursorPosition;

typedef struct editorStat{
  editorSetting setting;
  registers rgst;
  editorView view;
  cursorPosition cursor;
  char filename[256];
  int   y, // obsolete
        x, // obsolete
        currentLine,
        positionInCurrentLine,
        numOfLines, // obsolete
        lineDigit, // obsolete
        lineDigitSpace, // obsolete
        mode,
        cmdLoop,
        numOfChange,
        isViewUpdated, // obsolete
        debugMode,
        adjustLineNum, // obsolete
        trueLineCapa, // obsolete
        *trueLine; // obsolete
} editorStat;

#endif
