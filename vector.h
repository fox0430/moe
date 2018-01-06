#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<stdbool.h>

// Vector
#ifndef MOE_VECTOR_INCLUDE_H
typedef struct charArray{
  char* elements;
  int   capacity,
        head,
        numOfChar;
} charArray;

#define MOE_VECTOR_INCLUDE_H
#endif

// Function prototype
int charArrayInit(charArray* array);
int charArrayReserve(charArray* array, int capacity);
int charArrayPush(charArray* array, char element);
int charArrayInsert(charArray* array, char element, int position);
int charArrayPop(charArray* array);
int charArrayDel(charArray* array, int position);
bool charArrayIsEmpty(charArray* array);
int charArrayFree(charArray* array);
charArray* charArrayCopy(charArray*);
