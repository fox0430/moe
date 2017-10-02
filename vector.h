#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<stdbool.h>

// Vector
#ifndef VECTOR
typedef struct charArray{
  char* elements;
  int   capacity,
        head,
        numOfChar;
} charArray;
#endif

// Function prototype
int charArrayInit(charArray* array);
int charArrayReserve(charArray* array, int capacity);
int charArrayPush(charArray* array, char element);
int charArrayInsert(charArray* array, char element, int position);
int charArrayPop(charArray* array);
int charArrayDel(charArray* array, int position);
bool charArrayIsEmpty(charArray* array);
