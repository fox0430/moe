#include"gapbuffer.h"

int gapBufferInit(gapBuffer* gb){

  gb->buffer = (charArray**)malloc(sizeof(charArray*));
  gb->size = 0;
  gb->capacity = 1;
  gb->gapBegin = 0;
  gb->gapEnd = 1;
  return 1;
}

int gapBufferReserve(gapBuffer* gb, int capacity){

  if(capacity < gb->size || capacity <= 0){
    printf("Gapbuffer: New buffer capacity is too small.\n");
    return -1;
  }
  
  gapBufferMakeGap(gb, gb->capacity - (gb->gapEnd - gb->gapBegin));

  charArray** newBuffer = (charArray**)realloc(gb->buffer, sizeof(charArray*)*capacity);
  if(newBuffer == NULL){
    printf("Gapbuffer: Cannot reallocate new memory.\n");
    return -1;
  }

  gb->buffer = newBuffer;
  gb->gapBegin = gb->size;
  gb->gapEnd = capacity;
  gb->capacity = capacity;
  return 1;
}

// Create a gap starting with gapBegin
int gapBufferMakeGap(gapBuffer* gb,int gapBegin){

  if(gapBegin < 0 || gb->capacity-gapBegin < gb->gapEnd-gb->gapBegin){
    printf("Gapbuffer: Invalid position.\n");
    return -1;
  }

  if(gapBegin < gb->gapBegin){
    memmove(gb->buffer + (gb->gapEnd-gb->gapBegin+gapBegin), gb->buffer + gapBegin, sizeof(charArray*)*(gb->gapBegin-gapBegin));
  }else{
    int gapEnd = gapBegin + (gb->gapEnd-gb->gapBegin);
    memmove(gb->buffer+gb->gapBegin, gb->buffer+gb->gapEnd, sizeof(charArray*)*(gapEnd-gb->gapEnd));
  }
  gb->gapEnd = gapBegin + (gb->gapEnd-gb->gapBegin);
  gb->gapBegin = gapBegin;
  return 1;
}

//insertedPositionの直前に要素を挿入する.末尾に追加したい場合はinsertedPositionにバッファの要素数を渡す.
//ex.空のバッファに要素を追加する場合はinsertedPositionに0を渡す.
int gapBufferInsert(gapBuffer* gb, charArray* element, int position){

  if(position < 0 || gb->size < position){
    printf("Gapbuffer: Invalid position.\n");
    return -1;
  }

  if(gb->size == gb->capacity) gapBufferReserve(gb, gb->capacity*2);
  if(gb->gapBegin != position) gapBufferMakeGap(gb, position);
  gb->buffer[gb->gapBegin] = element;
  ++gb->gapBegin;
  ++gb->size;
  return 1;
}

// Deleted [begin,end] elements
int gapBufferDel(gapBuffer* gb, int begin, int end){

  if(begin > end || begin < 0 || gb->size < end){
    printf("Gapbuffer: Invalid interval.\n");
    return -1;
  }

  int begin_ = gb->gapBegin > begin ? begin : gb->gapEnd + (begin - gb->gapBegin),
      end_ = gb->gapBegin > end ? end : gb->gapEnd + (end - gb->gapBegin);

  if(begin_ <= gb->gapBegin && gb->gapEnd <= end_){
    gb->gapBegin = begin_;
    gb->gapEnd = end_;
  }else if(end_ <= gb->gapBegin){
    gapBufferMakeGap(gb, end_);
    gb->gapBegin = begin_;
  }else{
    memmove(gb->buffer + gb->gapBegin, gb->buffer + gb->gapEnd, sizeof(charArray*)*(begin_ - gb->gapEnd));
    gb->gapBegin = gb->gapBegin + begin_ - gb->gapEnd;
    gb->gapEnd = end_;
  }

  gb->size -= end - begin;
  while(gb->size > 0 && gb->size * 4 <= gb->capacity) if(gapBufferReserve(gb, gb->capacity / 2) == -1) return -1;
  return 1;
}

charArray* gapBufferAt(gapBuffer* gb, int index){

  if(index < 0 || gb->size <= index){
    printf("Gapbuffer: Invalid index.\n");
    exit(0);
  }
  if(index < gb->gapBegin) return gb->buffer[index];
  return gb->buffer[gb->gapEnd+(index - gb->gapBegin)];
}

bool gapBufferIsEmpty(gapBuffer* gb){
  return gb->capacity == gb->gapEnd - gb->gapBegin;
}
