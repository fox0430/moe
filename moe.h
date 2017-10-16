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

typedef struct editorStat{
  char filename[256];
  int   mode,
        lineDigit,
        lineDigitSpace,
        x,
        y,
        currentLine,
        numOfLines;
} editorStat;

// Function prototype
void startCurses();
void signal_handler(int SIG);
void exitCurses();
int writeFile(WINDOW **win, gapBuffer* gb, editorStat *stat);
int countLineDigit(int lineNum);
void printLineNum(WINDOW **win, int lineDigit, int line, int y);
void printLine(WINDOW **win, gapBuffer* gb, int lineDigit, int line, int y);
void commandBar(WINDOW **win, gapBuffer *gb, editorStat *stat);
void printStatBar(WINDOW **win, editorStat *stat);
int keyUp(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyDown(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyRight(gapBuffer* gb, editorStat* stat);
int keyLeft(gapBuffer* gb, editorStat* stat);
int keyBackSpace(WINDOW **win, gapBuffer* gb, editorStat* stat);
int keyEnter(WINDOW **win, gapBuffer* gb, editorStat* stat);
void normalMode(WINDOW **win, gapBuffer* gb, editorStat* stat);
void insertMode(WINDOW **win, gapBuffer* gb, editorStat* stat);
int newFile();
int openFile(char* filename);
