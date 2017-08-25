#include <malloc.h>
#include <stdio.h>
#include <stdbool.h>
#include <assert.h>
#include <string.h>

typedef struct charArray{
    char* elements;
    int capacity,   //確保したメモリ量
        head;       //次に要素をプッシュする位置
}charArray;

int charArrayInit(charArray* array){
    const int size=1; //realloc()の回数を少なくするためにあえて2以上にしてもいいかも
  
    array->elements=(char*)malloc(sizeof(char)*(size+1));
    if(array->elements == NULL){
        printf("Cannot allocate memory.");
        return -1;
    }
  
    array->elements[0]='\0';
    array->capacity=size;
    array->head=0;
    return 1;
}

int charArrayReserve(charArray* array,int capacity){
    if(array->head>capacity || capacity<=0){
        printf("New buffer capacity is too small.\n");
        return -1;
    }
    
    char* newElements=(char*)realloc(array->elements,sizeof(char)*(capacity+1));
    if(newElements==NULL){
        printf("Cannot reallocate new memory.\n");
        return -1;
    }

    array->elements=newElements;
    array->capacity=capacity;
    return 1;
}

int charArrayPush(charArray* array,char element){
    if(array->capacity==array->head && charArrayReserve(array,array->capacity*2)==-1) return -1;
    array->elements[array->head]=element;
    array->elements[array->head+1]='\0';
    ++array->head;
    return 1;
}

int charArrayPop(charArray* array){
    if(array->head==0){
        printf("Cannot pop from an empty array.");
        return -1;
    }
    --array->head;
    array->elements[array->head]='\0';

    if(array->head*4<=array->capacity && charArrayReserve(array,array->capacity/2)==-1) return -1;
    return 1;
}

bool charArrayIsEmpty(charArray* array){
    return array->head==0;
}

void charArrayTest(){
    charArray* array=(charArray*)malloc(sizeof(charArray));
    charArrayInit(array);

    for(int i=0; i<5; ++i) assert(charArrayPush(array,'a')!=-1);
    assert(array->capacity==8);
    assert(array->head==5);
    assert(strcmp(array->elements,"aaaaa")==0);

    for(int i=0; i<5; ++i) array->elements[i]='a'+i;

    assert(strcmp(array->elements,"abcde")==0);

    assert(charArrayPush(array,'F')==1);
    assert(charArrayPush(array,'G')==1);
    assert(charArrayPush(array,'H')==1);
    assert(charArrayPush(array,'I')==1);

    assert(array->capacity==16);
    assert(array->head==9);
    assert(strcmp(array->elements,"abcdeFGHI")==0);

    assert(charArrayPop(array)==1);
    assert(charArrayPop(array)==1);
    assert(charArrayPop(array)==1);
    assert(charArrayPop(array)==1);
    assert(charArrayPop(array)==1);

    assert(array->capacity==8);
    assert(array->head==4);
    assert(strcmp(array->elements,"abcd")==0);

    assert(charArrayPop(array)==1);
    assert(charArrayPop(array)==1);
    assert(charArrayPop(array)==1);
    assert(charArrayPop(array)==1);

    assert(charArrayIsEmpty(array));
    assert(array->capacity==1);

    printf("charArray test succeeded.\n");
}

int main(){
    charArrayTest();
}