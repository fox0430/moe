#ifndef MOE_VECTOR_INCLUDE_H
#define MOE_VECTOR_INCLUDE_H

typedef struct charArray{
  char* elements;
  int   capacity,
        head,
        numOfChar;
} charArray;

int charArrayInit(charArray* array);
int charArrayReserve(charArray* array, int capacity);
int charArrayPush(charArray* array, char element);
int charArrayInsert(charArray* array, char element, int position);
int charArrayPop(charArray* array);
int charArrayDel(charArray* array, int position);
bool charArrayIsEmpty(charArray* array);
int charArrayFree(charArray* array);
charArray* charArrayCopy(charArray*);
int charArrayCountRepeat(charArray* array, int start, char ch);

#endif
