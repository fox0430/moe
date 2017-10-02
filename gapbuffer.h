#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<stdbool.h>
#include<malloc.h>
#include"vector.h"

// Gapbuffer
#ifndef GAP_BUFFER
typedef struct gapBuffer{
  struct  charArray** buffer;
  int     size,       // 意味のあるデータが実際に格納されているサイズ
          capacity,   // Amount of secured memory
          gapBegin,
          gapEnd;     // 半開区間[gap_begin,gap_end)を隙間とする
} gapBuffer;
#endif

// Function prototype
int gapBufferInit(gapBuffer* gb);
int gapBufferReserve(gapBuffer* gb, int capacity);
int gapBufferMakeGap(gapBuffer* gb,int gapBegin);
int gapBufferInsert(gapBuffer* gb, charArray* element, int position);
int gapBufferDel(gapBuffer* gb, int begin, int end);
charArray* gapBufferAt(gapBuffer* gb, int index);
bool gapBufferIsEmpty(gapBuffer* gb);
