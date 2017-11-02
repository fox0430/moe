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
#define BRIGHT_WHITE 8

typedef struct editorStat{
  char filename[256];
  int   y,
        x,
        currentLine,
        numOfLines,
        lineDigit,
        lineDigitSpace,
        mode,
        numOfChange,
        debugMode;
} editorStat;

// Function prototype
int debugMode(WINDOW **win, gapBuffer *gb, editorStat *stat);
int setCursesColor();
void startCurses();
void signal_handler(int SIG);
void exitCurses();
int saveFile(WINDOW **win, gapBuffer* gb, editorStat *stat);
int countLineDigit(int lineNum);
void printLineNum(WINDOW **win, editorStat *stat, int currentLine, int y);
void printLine(WINDOW **win, gapBuffer* gb, editorStat *stat, int line, int y);
void printLineAll(WINDOW **win, gapBuffer* gb, editorStat *stat);
int commandBar(WINDOW **win, gapBuffer *gb, editorStat *stat);
void printStatBarInit(WINDOW **win, editorStat *stat);
void printStatBar(WINDOW **win, editorStat *stat);
int insNewLine(gapBuffer *gb, int position);
int keyUp(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyDown(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyRight(gapBuffer* gb, editorStat* stat);
int keyLeft(gapBuffer* gb, editorStat* stat);
int keyBackSpace(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyEnter(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyA(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyX(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyO(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyD(WINDOW **win, gapBuffer* gb, editorStat* stat);
void normalMode(WINDOW **win, gapBuffer* gb, editorStat* stat);
void insertMode(WINDOW **win, gapBuffer* gb, editorStat* stat);
int newFile();
int openFile(char* filename);
