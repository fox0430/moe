#include<malloc.h>
#include<stdio.h>
#include<stdbool.h>
#include<assert.h>
#include<stdlib.h>
#include<string.h>
#include<ncurses.h>

#define KEY_ESC 27

typedef struct charArray{
  char* elements;
  int capacity,
      head;
} charArray;


typedef struct gapBuffer{
  struct charArray** buffer;
  int capacity,   // Buffer lengs
      gapBegin,gapEnd; //半開区間[gap_begin,gap_end)を隙間とする
} gapBuffer;


void startCurses(){

  int h, w;
  initscr();      // start terminal contorl
  curs_set(1);    //set cursr
  keypad(stdscr, TRUE);   //enable cursr keys

  getmaxyx(stdscr, h, w);     // set window size
  scrollok(stdscr, TRUE);			// enable scroll

  start_color();      // color settings
  init_pair(1, COLOR_WHITE, COLOR_BLACK);     // set color strar is white and back is black
  init_pair(2, COLOR_GREEN, COLOR_BLACK);
  bkgd(COLOR_PAIR(1));    // set default color

  erase();	// screen display

  ESCDELAY = 25;      // delete esc key time lag

  move(0, 0);     // set default cursr point
}

int charArrayInit(charArray* array){
  int size=1;

  array->elements=(char*)malloc(sizeof(char)*(size+1));
  if(array->elements == NULL){
      printf("cannot allocate memory.");
      return -1;
  }

  array->elements[size]='\0';
  array->head=0;
  return 1;
}

int charArrayPush(charArray* array, int element){
  if(array->capacity == array->head){
    char* newElements = (char*)realloc(array->elements, sizeof(char)*(array->capacity *2+1));
    if(newElements == NULL){
      printf("cannot reallocate memory.");
      return -1;
      }
    array->elements = newElements;
    array->capacity *= 2;
    }

  array->elements[array->head] = element;
  array->elements[array->head +1] = '\0';
  ++array->head;
  return 1;
}

int charArrayPop(charArray* array){
  if(array->head == 0){
    printf("cannot pop from an empty array.");
    return -1;
  }
  --array->head;
  array->elements[array->head] = '\0';

  if(array->head*4 <= array->capacity){
    char* newElements = (char*)realloc(array->elements, sizeof(char)*(array->capacity /2+1));
      if(newElements == NULL){
        printf("cannot reallocate memory.");
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

int gapBufferInit(gapBuffer* gb){
  gb->buffer = NULL;
  gb->capacity = 0;
  gb->gapBegin = 0;
  gb->gapEnd = 0;
  return 1;
}

int gapBufferReserve(gapBuffer* gb, int capacity){
  if(capacity < gb->capacity - (gb->gapEnd - gb->gapBegin)){
    printf("New buffer capacity is too small.\n");
    return -1;
  }
  charArray** newBuffer=(charArray**)realloc(gb->buffer,sizeof(charArray*)*capacity);
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
  gb->gapEnd = capacity - (gb->capacity - gb->gapEnd);
  gb->capacity = capacity;
  return 1;
}

// Create a gap starting with gapBegin
int gapBufferMakeGap(gapBuffer* gb, int gapBegin){
  if(gapBegin < 0 || gb->capacity - gapBegin<gb->gapEnd-gb->gapBegin){
    printf("Invalid position.\n");
    return -1;
  }

  if(gapBegin<gb->gapBegin){
    // Rewrite memmove
    for(int i=0; i<gb->gapBegin-gapBegin; ++i){
      gb->buffer[gb->gapEnd-1-i]=gb->buffer[gb->gapBegin-1-i];
    }
  }else{
    // Rewrite memmove
    int gapEnd = gapBegin + (gb->gapEnd - gb->gapBegin);
    for(int i=0; i<gapEnd-gb->gapEnd; ++i){
    gb->buffer[gb->gapBegin + i] = gb->buffer[gb->gapEnd+i];
    }
  }
  gb->gapEnd = gapBegin + (gb->gapEnd-gb->gapBegin);
  gb->gapBegin = gapBegin;
  return 1;
}

//insertedPositionの直前に要素を挿入する.末尾に追加したい場合はinsertedPositionにバッファの要素数を渡す.
//ex.空のバッファに要素を追加する場合はinsertedPositionに0を渡す.
int gapBufferInsert(gapBuffer* gb, charArray* element, int insertedPosition){
  if(0 > insertedPosition || insertedPosition>gb->capacity - (gb->gapEnd - gb->gapBegin)){
    printf("Invalid position.\n");
    return -1;
  }

  if(gb->gapEnd - gb->gapBegin == 0){
    if(gb->buffer == NULL){
      gb->buffer = (charArray**)malloc(sizeof(charArray*));
      gb->capacity = 1;
      gb->gapBegin = 0;
      gb->gapEnd = 1;
    }else gapBufferReserve(gb, gb->capacity *2);
  }
  if(gb->gapBegin != insertedPosition) gapBufferMakeGap(gb, insertedPosition);
  gb->buffer[gb->gapBegin] = element;
  ++gb->gapBegin;
  return 1;
}

// Deleted [begin,end] elements
int gapBufferDel(gapBuffer* gb, int begin, int end){
  if(begin > end || 0 < begin || gb->capacity - (gb->gapEnd - gb->gapBegin) < end){
    printf("Invalid interval.\n");
    return -1;
  }

  int begin_ = gb->gapBegin > begin ? begin : gb->gapEnd + (begin - gb->gapBegin),
    end_ = gb->gapBegin>end ? end : gb->gapEnd + (end - gb->gapBegin);

  if(begin_ <= gb->gapBegin && gb->gapEnd <= end_){
    gb->gapBegin = begin_;
    gb->gapEnd = end_;
  }else if(end_ <= gb->gapBegin){
    gapBufferMakeGap(gb, end_);
    gb->gapBegin = begin_;
  }else{
    memmove(gb->buffer + gb->gapBegin, gb->buffer + gb->gapEnd, begin_ - gb->gapEnd);
    gb->gapBegin = gb->gapBegin + begin_ - gb->gapEnd;
    gb->gapEnd = end_;
  }

  if((gb->capacity - (gb->gapEnd - gb->gapBegin)) *4 <= gb->capacity){
    gapBufferReserve(gb, gb->capacity /2);
  }
  return 1;
}

charArray* gapBufferAt(gapBuffer* gb, int index){
  if(index < 0 || gb->capacity - (gb->gapEnd-gb->gapBegin) <= index){
    printf("Invalid index.\n");
    exit(0);
  }
  if(index < gb->gapBegin) return gb->buffer[index];
  return gb->buffer[gb->gapEnd + (index-gb->gapBegin)];
}

bool gapBufferIsEmpty(gapBuffer* gb){
  return gb->capacity == gb->gapEnd - gb->gapBegin;
}

void EditChar(gapBuffer* gb, int lineNum){
  
  int key,
      y = 0,
      x = 2;

  while(1){

    move(y, x);
    refresh();
    noecho();
    key = getch();

    if(key == KEY_ESC) {
      break;
    }

    switch(key){
      case KEY_UP:
        y--;
        break;

      case KEY_DOWN:
        if(lineNum <= y) break;
        y++;
        break;

      case KEY_RIGHT:
        x++;
        break;

      case KEY_LEFT:
        if(x <= 2) break;
        x--;
        break;

      case KEY_BACKSPACE:   // !! Not actually deleted
        x--;
        move(y, x);
        delch();
        break;

      default:    // !! Not actually insart
        echo();
        insch(key);
    }
  }
}

int openFile(char* filename){

  char ch;
  int lineNum = 0;

  FILE *fp = fopen(filename, "r");
  if(fp == NULL){
		printf("%s Cannot file open... \n", filename);
		exit(0);
  }

  gapBuffer* gb = (gapBuffer*)malloc(sizeof(gapBuffer));
  gapBufferInit(gb);
  {
    charArray* ca = (charArray*)malloc(sizeof(charArray));
    charArrayInit(ca);
    gapBufferInsert(gb, ca, 0);
  }

  while((ch = fgetc(fp)) != EOF){
    if(ch=='\n'){
      ++lineNum;
      charArray* ca = (charArray*)malloc(sizeof(charArray));
      charArrayInit(ca);
      gapBufferInsert(gb, ca, lineNum);
    }else charArrayPush(gapBufferAt(gb, lineNum), ch);
  }
  fclose(fp);

  startCurses();  

  bkgd(COLOR_PAIR(1));
  
  for(int i=0; i<lineNum; ++i) {
    bkgd(COLOR_PAIR(2));
    printw("%d:", i+1); // line number  !! Rewrite
    bkgd(COLOR_PAIR(1));
    printw("%s\n", gapBufferAt(gb, i)->elements);
  }

  EditChar(gb, lineNum);

	return 0;
}

int main(int argc,char* argv[]){

  openFile(argv[1]);
  endwin();

  return 0;
}
