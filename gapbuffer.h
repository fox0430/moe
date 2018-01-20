#ifndef MOE_GAP_BUFFER_H
#define MOE_GAP_BUFFER_H

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <malloc.h>
#include "chararray.h"

typedef struct gapBuffer{
  struct  charArray** buffer;
  int     size,       // 意味のあるデータが実際に格納されているサイズ
          capacity,   // Amount of secured memory
          gapBegin,
          gapEnd;     // 半開区間[gap_begin,gap_end)を隙間とする
  /*
    ギャップには有効なポインタを格納しないようにする.
    逆にギャップ以外の部分には有効なポインタのみ格納する.
  */
} gapBuffer;


// Function prototype
int gapBufferInit(gapBuffer* gb);
int gapBufferReserve(gapBuffer* gb, int capacity);
int gapBufferMakeGap(gapBuffer* gb,int gapBegin);
int gapBufferInsert(gapBuffer* gb, charArray* element, int position);
int gapBufferDel(gapBuffer* gb, int begin, int end);
charArray* gapBufferAt(gapBuffer* gb, int index);
bool gapBufferIsEmpty(gapBuffer* gb);
int gapBufferFree(gapBuffer* gb);

#endif
