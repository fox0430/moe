#include <malloc.h>
#include <stdio.h>
#include <stdbool.h>
#include <assert.h>

typedef struct charArray{
    char* elements;
    int capacity,head;
}charArray;

int charArrayInit(charArray* array,int size,int init_value){
    int size_=1; //realloc()の回数を少なくするためにあえて2以上にしてもいいかも
    while(size_<size) size_*=2;

    array->elements=(char*)malloc(sizeof(char)*(size_+1));
    if(array->elements == NULL){
        printf("cannot allocate memory.");
        return -1;
    }

    for(int i=0; i<size; ++i) array->elements[i]=init_value;
    array->elements[size]='\0';
    array->capacity=size_;
    array->head=size;
    return 1;
}

int charArrayPush(charArray* array,char element){
    if(array->capacity==array->head){
        char* newElements=(char*)realloc(array->elements,sizeof(char)*(array->capacity*2+1));
        if(newElements == NULL){
            printf("cannot reallocate memory.");
            return -1;
        }
        array->elements=newElements;
        array->capacity*=2;
    }

    array->elements[array->head]=element;
    array->elements[array->head+1]='\0';
    ++array->head;
    return 1;
}

int charArrayPop(charArray* array){
    if(array->head==0){
        printf("cannot pop from an empty array.");
        return -1;
    }
    --array->head;
    array->elements[array->head]='\0';

    if(array->head*4<=array->capacity){
        char* newElements=(char*)realloc(array->elements,sizeof(char)*(array->capacity/2+1));
        if(newElements == NULL){
            printf("cannot reallocate memory.");
            return -1;
        }
        array->elements=newElements;
        array->capacity/=2;
    }
    return 1;
}

bool charArrayIsEmpty(charArray* array){
    return array->head==0;
}

void charArrayTest(){
    charArray array;
    charArrayInit(&array,5,'a');
    
    assert(array.capacity==8);
    assert(array.head==5);
    assert(array.elements=="aaaaa");

    for(int i=0; i<5; ++i) array.elements[i]='a'+i;

    assert(array.elements=="abcde");

    charArrayPush(&array,'F');
    charArrayPush(&array,'G');
    charArrayPush(&array,'H');
    charArrayPush(&array,'I');

    assert(array.capacity==16);
    assert(array.head==9);
    assert(array.elements=="abcdeFGHI");

    charArrayPop(&array);
    charArrayPop(&array);
    charArrayPop(&array);
    charArrayPop(&array);
    charArrayPop(&array);

    assert(array.capacity==8);
    assert(array.head==4);
    assert(array.elements=="abcd");

    charArrayPop(&array);
    charArrayPop(&array);
    charArrayPop(&array);
    charArrayPop(&array);

    assert(charArrayIsEmpty(&array));
    assert(array.capacity==1);
}

int main(){
}