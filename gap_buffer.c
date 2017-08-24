#include <stdio.h>
#include <malloc.h>
#include <assert.h>
#include <string.h>
#include <stdbool.h>

#define TYPE1 int //ここでは仮にintとしておくが実際にはline*のようになると思われる

typedef struct gapBuffer{
    TYPE1* buffer;
    int capacity,              //bufferの長さ
        gapBegin,gapEnd; //半開区間[gap_begin,gap_end)を隙間とする
}gapBuffer; //実際にはtxt?

int gapBufferInit(gapBuffer* gb){
    gb->buffer=NULL;
    gb->capacity=0;
    gb->gapBegin=0;
    gb->gapEnd=0;
    return 1;
}

//現在の実装ではもしリサイズ後のサイズが現在の要素数よりも少ない場合はreturn -1をするようになっている.
//はみ出した部分についてはクリップするように実装を変更しても良いかもしれない.
int gapBufferReserve(gapBuffer* gb,int capacity){
    if(capacity<gb->capacity-(gb->gapEnd-gb->gapBegin)){
        printf("New buffer capacity is too small.\n");
        return -1;
    }
    TYPE1* newBuffer=(TYPE1*)realloc(gb->buffer,sizeof(TYPE1)*capacity);
    if(newBuffer==NULL){
        printf("Cannot reallocate new memory.\n");
        return -1;
    }

    gb->buffer=newBuffer;
    memmove(gb->buffer+(capacity-(gb->capacity-gb->gapEnd)),gb->buffer+(gb->capacity-(gb->capacity-gb->gapEnd)),(gb->capacity-gb->gapEnd));
    /*
    for(int i=0; i<gb->capacity-gb->gapEnd; ++i){
        gb->buffer[capacity-1-i]=gb->buffer[gb->capacity-1-i];
    }
    */
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
        //memmoveに書き直す
        for(int i=0; i<gb->gapBegin-gapBegin; ++i){
            gb->buffer[gb->gapEnd-1-i]=gb->buffer[gb->gapBegin-1-i];
        }
    }else{
        //memmoveに書き直す
        int gapEnd=gapBegin+(gb->gapEnd-gb->gapBegin);
        for(int i=0; i<gapEnd-gb->gapEnd; ++i){
            gb->buffer[gb->gapBegin+i]=gb->buffer[gb->gapEnd+i];
        }
    }
    gb->gapEnd=gapBegin+(gb->gapEnd-gb->gapBegin);
    gb->gapBegin=gapBegin;
    return 1;
}

//insertedPositionの直前に要素を挿入する.末尾に追加したい場合はinsertedPositionにバッファの要素数を渡す.
//ex.空のバッファに要素を追加する場合はinsertedPositionに0を渡す.
int gapBufferInsert(gapBuffer* gb,TYPE1 element,int insertedPosition){
    if(0>insertedPosition || insertedPosition>gb->capacity-(gb->gapEnd-gb->gapBegin)){
        printf("Invalid position.\n");
        return -1;
    }

    if(gb->gapEnd-gb->gapBegin==0){
        if(gb->buffer==NULL){
            gb->buffer=(TYPE1*)malloc(sizeof(TYPE1));
            gb->capacity=1;
            gb->gapBegin=0;
            gb->gapEnd=1;
        }else gapBufferReserve(gb,gb->capacity*2);
    }
    if(gb->gapBegin!=insertedPosition) gapBufferMakeGap(gb,insertedPosition);
    gb->buffer[gb->gapBegin]=element;
    ++gb->gapBegin;
    return 1;
}

//[begin,end)の要素を削除する
int gapBufferErase(gapBuffer* gb,int begin,int end){
    if(begin>end || 0<begin || gb->capacity-(gb->gapEnd-gb->gapBegin)<end){
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
        memmove(gb->buffer+gb->gapBegin,gb->buffer+gb->gapEnd,begin_-gb->gapEnd);
        gb->gapBegin=gb->gapBegin+begin_-gb->gapEnd;
        gb->gapEnd=end_;
    }

    if((gb->capacity-(gb->gapEnd-gb->gapBegin))*4<=gb->capacity){
        gapBufferReserve(gb,gb->capacity/2);
    }
    return 1;
}

TYPE1 gapBufferAt(gapBuffer* gb,int index){
    if(index<0 || gb->capacity-(gb->gapEnd-gb->gapBegin)<=index){
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
    gapBufferInit(gb);
    
    gapBufferInsert(gb,0,0);
    assert(gapBufferAt(gb,0)==0);
    for(int i=1; i<8; ++i) gapBufferInsert(gb,i,i);
    for(int i=0; i<8; ++i) assert(gapBufferAt(gb,i)==i);

    gapBufferErase(gb,0,5);
    for(int i=0; i<3; ++i) assert(gapBufferAt(gb,i)==i+5);
    
    gapBufferErase(gb,0,2);
    assert(gapBufferAt(gb,0)==7);
    
    gapBufferErase(gb,0,1);

    assert(gapBufferIsEmpty(gb));

    gapBufferInsert(gb,0,0);
    gapBufferInsert(gb,1,0);
    gapBufferInsert(gb,2,0); //2   1   0
    gapBufferInsert(gb,3,2); //2   1 3 0
    gapBufferInsert(gb,4,1); //2 4 1 3 0

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