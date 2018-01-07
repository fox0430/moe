#include"vector.h"

int charArrayInit(charArray* array){

  const int size = 1;

  array->elements = (char*)malloc(sizeof(char)*(size +1));
  if(array->elements == NULL){
      printf("Vector: cannot allocate memory.");
      return -1;
  }

  array->elements[0] = '\0';
  array->capacity = size;
  array->head = 0;
  array->numOfChar = 0;
  return 1;
}

int charArrayReserve(charArray* array, int capacity){

  if(array->head > capacity || capacity < 0){
      printf("Vector: New buffer capacity is too small.\n");
      return -1;
  }

  char* newElements = (char*)realloc(array->elements, sizeof(char)*(capacity +1));
  if(newElements == NULL){
      printf("Vector: cannot reallocate new memory.\n");
      return -1;
  }

  array->elements = newElements;
  array->capacity = capacity;
  return 1;
}

int charArrayPush(charArray* array, char element){

  if(array->capacity == array->head && charArrayReserve(array, array->capacity *2) ==- 1) return -1;
  array->elements[array->head] = element;
  array->numOfChar++;
  array->elements[array->head+1] = '\0';
  ++array->head;
  return 1;
}

int charArrayInsert(charArray* array, char element, int position){

  if(array->capacity == array->head && charArrayReserve(array, array->capacity *2) == -1) return -1;

  memmove(array->elements + position, array->elements + position -1, array->head - position +1);
  array->elements[position] = element;
  array->numOfChar++;
  array->elements[array->head+1] = '\0';
  ++array->head;
  return 1;
}

int charArrayPop(charArray* array){

  if(array->head == 0){
    printf("Vector: cannot pop from an empty array.");
    return -1;
  }
  
  --array->head;
  array->elements[array->head] = '\0';

  --array->numOfChar;

  if(array->head * 4 <= array->capacity){
    char* newElements = (char*)realloc(array->elements, sizeof(char) * (array->capacity / 2 + 1));
    if(newElements == NULL){
        printf("Vector: cannot reallocate memory.");
        return -1;
    }
    array->elements = newElements;
    array->capacity /= 2;
  }
  return 1;
}

int charArrayDel(charArray* array, int position){

  if(array->head == 0){
    printf("Vector: cannot pop from an empty array.");
    return -1;
  }

  memmove(array->elements + position, array->elements + position + 1, array->head - position - 1);
  charArrayPop(array);

  if(array->head*4 <= array->capacity){
    char* newElements = (char*)realloc(array->elements, sizeof(char)*(array->capacity /2+1));
      if(newElements == NULL){
        printf("Vector: cannot reallocate memory.");
        return -1;
        }
     array->elements = newElements;
     array->capacity /= 2;
  }
  return 1;
}

bool charArrayIsEmpty(charArray* array){
  return array->head == 0;
}

int charArrayFree(charArray* array){
  if(array->elements == NULL){
    printf("Vector: cannot free null array.");
    return -1;
  }

  free(array->elements);
  
  return 1;
}

charArray* charArrayCopy(charArray* array){
  charArray* copy = (charArray*)malloc(sizeof(charArray));
  charArrayInit(copy);
  for(int i = 0; i < array->numOfChar; ++i) charArrayPush(copy, array->elements[i]);
  return copy;
}
