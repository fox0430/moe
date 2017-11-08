#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<stdbool.h>
#include<malloc.h>
#include<signal.h>
#include<ncurses.h>
#include"gapbuffer.h"
//#include<locale.h>

#define KEY_ESC 27
#define COLOR_DEFAULT -1
#define BRIGHT_WHITE 231
#define BRIGHT_GREEN 85 
#define GRAY 245
#define ON 1
#define OFF 0
#define NORMAL_MODE 0
#define INSERT_MODE 1

typedef struct registers{
  gapBuffer *yankedLine;
  charArray *yankedStr;
  int numOfYankedLines,
      numOfYankedStr;
} registers;

typedef struct editorStat{
  registers rgst;
  char filename[256];
  int   y,
        x,
        currentLine,
        numOfLines,
        lineDigit,
        lineDigitSpace,
        mode,
        cmdLoop,
        numOfChange,
        isViewUpdated,
        debugMode;
} editorStat;

// Function prototype
int debugMode(WINDOW **win, gapBuffer *gb, editorStat *stat);
void winInit(WINDOW **win);
void winResizeMove(WINDOW *win, int lines, int columns, int y, int x);
int setCursesColor();
void startCurses();
void signal_handler(int SIG);
void exitCurses();
void winResizeEvent(WINDOW **win, gapBuffer *gb, editorStat *stat);
void editorStatInit(editorStat* stat);
void registersInit(editorStat *stat);
int saveFile(WINDOW **win, gapBuffer* gb, editorStat *stat);
int countLineDigit(int lineNum);
void printCurrentLine(WINDOW **win, gapBuffer *gb, editorStat *stat);
void printLineNum(WINDOW **win, editorStat *stat, int currentLine, int y);
void printLine(WINDOW **win, gapBuffer* gb, editorStat *stat, int currentLine, int y);
void printLineAll(WINDOW **win, gapBuffer* gb, editorStat *stat);
void printStatBarInit(WINDOW **win, gapBuffer *gb, editorStat *stat);
void printStatBar(WINDOW **win, gapBuffer *gb, editorStat *stat);
int commandBar(WINDOW **win, gapBuffer *gb, editorStat *stat);
int insNewLine(gapBuffer *gb, editorStat *stat, int position);
int insIndent(gapBuffer *gb, editorStat *stat);
int insertTab(gapBuffer *gb, editorStat *stat);
int lineYank(gapBuffer *gb, editorStat *stat);
int keyUp(gapBuffer* gb, editorStat* stat);
int keyDown(gapBuffer* gb, editorStat* stat);
int keyRight(gapBuffer* gb, editorStat* stat);
int keyLeft(gapBuffer* gb, editorStat* stat);
int keyBackSpace(gapBuffer* gb, editorStat* stat);
int keyEnter(gapBuffer* gb, editorStat* stat);
int keyX(gapBuffer* gb, editorStat* stat);
int keyA(gapBuffer *gb, editorStat *stat);
int keyO(gapBuffer* gb, editorStat* stat);
int keyD(WINDOW **win, gapBuffer* gb, editorStat* stat);
int moveFirstLine(WINDOW **win, gapBuffer* gb, editorStat* stat);
int moveLastLine(gapBuffer* gb, editorStat* stat);
int charInsert(gapBuffer *gb, editorStat *stat, int key);
void cmdNormal(WINDOW **win, gapBuffer *gb, editorStat *stat, int key);
void normalMode(WINDOW **win, gapBuffer* gb, editorStat* stat);
void insertMode(WINDOW **win, gapBuffer* gb, editorStat* stat);
int newFile();
int openFile(char* filename);
