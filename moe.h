#include"gapbuffer.h"
#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<stdbool.h>
#include<malloc.h>
#include<ncurses.h>
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
void exitCurses();
int writeFile(gapBuffer* gb);
int countLineDigit(int lineNum);
void printLineNum(int lineDigit, int line, int y);
void printLine(gapBuffer* gb, int lineDigit, int line, int y);
int keyUp(gapBuffer* gb, editorStat* stat);
int keyDown(gapBuffer* gb, editorStat* stat);
int keyRight(gapBuffer* gb, editorStat* stat);
int keyLeft(gapBuffer* gb, editorStat* stat);
int keyBackSpace(gapBuffer* gb, editorStat* stat);
int keyEnter(gapBuffer* gb, editorStat* stat);
void insertMode(gapBuffer* gb, editorStat* stat);
int newFile();
int openFile(char* filename);
