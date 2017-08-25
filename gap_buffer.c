#include <stdio.h>
#include <malloc.h>
#include <assert.h>
#include <string.h>
#include <stdbool.h>

#define TYPE1 int //ここでは仮にintとしておくが実際にはline*のようになると思われる

typedef struct gapBuffer{
    TYPE1* buffer;
    int size,            //意味のあるデータが実際に格納されているサイズ
        capacity,        //確保したメモリ量
        gapBegin,gapEnd; //半開区間[gap_begin,gap_end)を隙間とする
}gapBuffer; //実際にはtxt?

int gapBufferInit(gapBuffer* gb){
    gb->buffer=(TYPE1*)malloc(sizeof(TYPE1));
    gb->size=0;
    gb->capacity=1;
    gb->gapBegin=0;
    gb->gapEnd=1;
    return 1;
}

int gapBufferReserve(gapBuffer* gb,int capacity){
    if(capacity<gb->size || capacity<=0){
        printf("New buffer capacity is too small.\n");
        return -1;
    }
    TYPE1* newBuffer=(TYPE1*)realloc(gb->buffer,sizeof(TYPE1)*capacity);
    if(newBuffer==NULL){
        printf("Cannot reallocate new memory.\n");
        return -1;
    }

    gb->buffer=newBuffer;
    memmove(gb->buffer+(capacity-(gb->capacity-gb->gapEnd)),gb->buffer+(gb->capacity-(gb->capacity-gb->gapEnd)),sizeof(TYPE1)*(gb->capacity-gb->gapEnd));
    gb->gapEnd=capacity-(gb->capacity-gb->gapEnd);
    gb->capacity=capacity;
    return 1;
}

//gapBeginから始まる隙間を作る
int gapBufferMakeGap(gapBuffer* gb,int gapBegin){
    if(gapBegin<0 || gb->capacity-gapBegin<gb->gapEnd-gb->gapBegin){
        printf("Invalid position.\n");
        return -1;
    }

    if(gapBegin<gb->gapBegin){
        memmove(gb->buffer+(gb->gapEnd-gb->gapBegin+gapBegin),gb->buffer+gapBegin,sizeof(TYPE1)*(gb->gapBegin-gapBegin));
    }else{
        int gapEnd=gapBegin+(gb->gapEnd-gb->gapBegin);
        memmove(gb->buffer+gb->gapBegin,gb->buffer+gb->gapEnd,sizeof(TYPE1)*(gapEnd-gb->gapEnd));
    }
    gb->gapEnd=gapBegin+(gb->gapEnd-gb->gapBegin);
    gb->gapBegin=gapBegin;
    return 1;
}

//insertedPositionの直前に要素を挿入する.末尾に追加したい場合はinsertedPositionにバッファの要素数を渡す.
//ex.空のバッファに要素を追加する場合はinsertedPositionに0を渡す.
int gapBufferInsert(gapBuffer* gb,int position,TYPE1 element){
    if(position<0 || gb->size<position){
        printf("Invalid position.\n");
        return -1;
    }

    if(gb->size==gb->capacity) gapBufferReserve(gb,gb->capacity*2);
    if(gb->gapBegin!=position) gapBufferMakeGap(gb,position);
    gb->buffer[gb->gapBegin]=element;
    ++gb->gapBegin;
    ++gb->size;
    return 1;
}

//[begin,end)の要素を削除する
int gapBufferErase(gapBuffer* gb,int begin,int end){
    if(begin>end || begin<0 || gb->size<end){
        printf("Invalid interval.\n");
        return -1;
    }

    int begin_=gb->gapBegin>begin?begin:gb->gapEnd+(begin-gb->gapBegin),
        end_=gb->gapBegin>end?end:gb->gapEnd+(end-gb->gapBegin);

    if(begin_<=gb->gapBegin && gb->gapEnd<=end_){
        gb->gapBegin=begin_;
        gb->gapEnd=end_;
    }else if(end_<=gb->gapBegin){
        gapBufferMakeGap(gb,end_);
        gb->gapBegin=begin_;
    }else{
        memmove(gb->buffer+gb->gapBegin,gb->buffer+gb->gapEnd,sizeof(TYPE1)*(begin_-gb->gapEnd));
        gb->gapBegin=gb->gapBegin+begin_-gb->gapEnd;
        gb->gapEnd=end_;
    }

    gb->size-=end-begin;
    while(gb->size>0 && gb->size*4<=gb->capacity) if(gapBufferReserve(gb,gb->capacity/2)==-1) return -1;
    return 1;
}

TYPE1 gapBufferAt(gapBuffer* gb,int index){
    if(index<0 || gb->size<=index){
        printf("Invalid index.\n");
        return -1;
    }
    if(index<gb->gapBegin) return gb->buffer[index];
    return gb->buffer[gb->gapEnd+(index-gb->gapBegin)];
}

bool gapBufferIsEmpty(gapBuffer* gb){
    return gb->capacity==gb->gapEnd-gb->gapBegin;
}


void gapBufferTest(){
    gapBuffer* gb=(gapBuffer*)malloc(sizeof(gapBuffer));
    assert(gapBufferInit(gb)==1);
    
    assert(gapBufferInsert(gb,0,0)==1);
    assert(gapBufferAt(gb,0)==0);
    for(int i=1; i<8; ++i) assert(gapBufferInsert(gb,i,i)==1);
    for(int i=0; i<8; ++i) assert(gapBufferAt(gb,i)==i);

    assert(gapBufferErase(gb,0,5)==1);
    assert(gapBufferErase(gb,1,0)==-1);
    for(int i=0; i<3; ++i) assert(gapBufferAt(gb,i)==i+5);
    
    assert(gapBufferErase(gb,0,2)==1);
    assert(gapBufferAt(gb,0)==7);
    
    gapBufferErase(gb,0,1);

    assert(gapBufferIsEmpty(gb));
    assert(gapBufferErase(gb,0,1)==-1);

    assert(gapBufferInsert(gb,0,0)==1);
    assert(gapBufferInsert(gb,0,1)==1);
    assert(gapBufferInsert(gb,0,2)==1); //2   1   0
    assert(gapBufferInsert(gb,2,3)==1); //2   1 3 0
    assert(gapBufferInsert(gb,1,4)==1); //2 4 1 3 0
    assert(gapBufferInsert(gb,6,0)==-1);

    assert(gapBufferAt(gb,0)==2);
    assert(gapBufferAt(gb,1)==4);
    assert(gapBufferAt(gb,2)==1);
    assert(gapBufferAt(gb,3)==3);
    assert(gapBufferAt(gb,4)==0);

    assert(gapBufferReserve(gb,4)==-1);

    printf("gapBuffer test succeeded.\n");
}

int main(){
    gapBufferTest();
    return 0;
}