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
      head,
      numOfChar;
} charArray;

typedef struct gapBuffer{
  struct charArray** buffer;
  int size,       //意味のあるデータが実際に格納されているサイズ
      capacity,   //Amount of secured memory
      gapBegin,
      gapEnd;     //半開区間[gap_begin,gap_end)を隙間とする
}gapBuffer;

typedef struct editorStat{
  int mode,
      lineDigitSpace;
}editorStat;


void startCurses(){

  int h,
      w;

  initscr();      // start terminal contorl
  curs_set(1);    // set cursr
  keypad(stdscr, TRUE);   // enable cursr keys

  getmaxyx(stdscr, h, w);     // set window size

  start_color();      // color settings
  init_pair(1, COLOR_WHITE, COLOR_BLACK);     // set color strar is white and back is black
  init_pair(2, COLOR_GREEN, COLOR_BLACK);
  init_pair(3, COLOR_CYAN, COLOR_BLACK);

  erase();  	// screen display

  ESCDELAY = 25;    // delete esc key time lag

  move(0, 0);     // set cursr point
}

void exitCurses(){
 endwin(); 
}

void editorStatInit(){
  
  editorStat* stat;
  stat->mode = 0;
  stat->lineDigitSpace = 0;
}

int charArrayInit(charArray* array){

  const int size = 1;

  array->elements = (char*)malloc(sizeof(char)*(size +1));
  if(array->elements == NULL){
      printf("Cannot allocate memory.");
      return -1;
  }

  array->elements[0] = '\0';
  array->capacity = size;
  array->head = 0;
  return 1;
}

int charArrayReserve(charArray* array, int capacity){

  if(array->head > capacity || capacity <= 0){
      printf("New buffer capacity is too small.\n");
      return -1;
  }

  char* newElements = (char*)realloc(array->elements, sizeof(char)*(capacity +1));
  if(newElements == NULL){
      printf("Cannot reallocate new memory.\n");
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

int charArrayDel(charArray* array, int position){

  if(array->head == 0){
    printf("cannot pop from an empty array.");
    return -1;
  }

  memmove(array->elements + position - 1, array->elements + position, array->numOfChar - position);
  --array->numOfChar;
  charArrayPop(array);

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

  gb->buffer = (charArray**)malloc(sizeof(charArray*));
  gb->size = 0;
  gb->capacity = 1;
  gb->gapBegin = 0;
  gb->gapEnd = 1;
  return 1;
}

int gapBufferReserve(gapBuffer* gb, int capacity){

  if(capacity < gb->size || capacity <= 0){
    printf("New buffer capacity is too small.\n");
    return -1;
  }
  charArray** newBuffer = (charArray**)realloc(gb->buffer, sizeof(charArray*)*capacity);
  if(newBuffer == NULL){
    printf("Cannot reallocate new memory.\n");
    return -1;
  }

  gb->buffer = newBuffer;
  memmove(gb->buffer + (capacity - (gb->capacity - gb->gapEnd)),
    gb->buffer + (gb->capacity - (gb->capacity - gb->gapEnd)),sizeof(charArray*)*(gb->capacity - gb->gapEnd));
  gb->gapEnd = capacity - (gb->capacity - gb->gapEnd);
  gb->capacity = capacity;
  return 1;
}

// Create a gap starting with gapBegin
int gapBufferMakeGap(gapBuffer* gb,int gapBegin){

  if(gapBegin < 0 || gb->capacity-gapBegin < gb->gapEnd-gb->gapBegin){
    printf("Invalid position.\n");
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
    printf("Invalid position.\n");
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
    printf("Invalid interval.\n");
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
  while(gb->size > 0 && gb->size *4 <= gb->capacity) if(gapBufferReserve(gb, gb->capacity /2) == -1) return -1;
  return 1;
}

charArray* gapBufferAt(gapBuffer* gb, int index){

  if(index < 0 || gb->size <= index){
    printf("Invalid index.\n");
    exit(0);
  }
  if(index < gb->gapBegin) return gb->buffer[index];
  return gb->buffer[gb->gapEnd+(index - gb->gapBegin)];
}

bool gapBufferIsEmpty(gapBuffer* gb){
  return gb->capacity == gb->gapEnd - gb->gapBegin;
}

int writeFile(gapBuffer* gb){
  
  FILE *fp;
  char *filename = "test_new.txt";

   if ((fp = fopen(filename, "w")) == NULL) {
    printf("%s Cannot file open... \n", filename);
      return -1;
    }
  
  for(int i=0; i < gb->size; i++){
    fputs(gapBufferAt(gb, i)->elements, fp);
    if(i != gb->size -1 ) fputc('\n', fp);
  }

  fclose(fp);

  return 0;
}

int countLineDigit(int lineNum){

  int lineDigit = 0;
  while(lineNum > 0){
    lineNum /= 10;
    lineDigit++;
  }
  return lineDigit;
}

void PrintLineNum(int lineDigit, int position){

  int lineDigitSpace = lineDigit - countLineDigit(position + 1);
  for(int i=0; i<lineDigitSpace; i++) printw(" ");
  bkgd(COLOR_PAIR(2));
  printw("%d:", position + 1); 
}

void printStr(gapBuffer* gb, int lineDigit, int position){

  for(int i = position; i < gb->size - 1; i++) {
    if(i >= LINES) break;
    PrintLineNum(lineDigit, i);
    bkgd(COLOR_PAIR(1));
    printw("%s\n", gapBufferAt(gb, i)->elements);
  }
}

/*
void printMode(){
  mvprintw(LINES-1, 0, "mode:");
  bkgd(COLOR_PAIR(3));
  mvprintw(LINES-1, 5, "Insert");
  bkgd(COLOR_PAIR(1));
}
*/

/*
void nomalMode(gapBuffer* gb, int lineDigit, int lineNum){

  int key,
    y = 0;
    x = lineDigit + 1;
    
  while(1){
    move(y, x);
    refresh();
    noecho();
    key = getch();

    switch(key){
    
      case 'k':
        if(y < 1) break;
        else if(x == gapBufferAt(gb, y)->numOfChar + lineDigit || x > gapBufferAt(gb, y-1)->numOfChar + lineDigit){
          y--;
          x = gapBufferAt(gb,y)->numOfChar + lineDigit;
          break;
        }
        y--;
        break;

      case 'j':
        if(y >= gb->size - 2) break;
        else if(x == gapBufferAt(gb, y)->numOfChar + lineDigit || x >= gapBufferAt(gb, y+1)->numOfChar + lineDigit) {
          y++;
          x = gapBufferAt(gb, y)->numOfChar + lineDigit;
          break;
        }
          y++;
        break;

      case 'h':
        if(x >= gapBufferAt(gb, y)->numOfChar + lineDigit + 1) break;
        x++;
        break;

      case 'l':
        if(x == lineDigit + 1) break;
        x--;
        break;
      
      case 'i':
        insertMode(gb, lineDigit, lineNum);
        break;
      
      default:
        break;
    }
  }
}
*/

void insertMode(gapBuffer* gb, int lineDigit, int lineNum){

  int key,
      y = 0,
      x = lineDigit + 1;

  while(1){

    move(y, x);
    refresh();
    noecho();
    key = getch();

    if(key == KEY_ESC) {
      writeFile(gb);
      exitCurses();
      break;
    }
/*
    if(key == KEY_ESC) {
      nomalMode(gb, lineDigit, lineNum);
    }
*/
    switch(key){

      case KEY_UP:
        if(y < 1) break;
        else if(x == gapBufferAt(gb, y)->numOfChar + lineDigit || x > gapBufferAt(gb, y-1)->numOfChar + lineDigit){
          y--;
          x = gapBufferAt(gb,y)->numOfChar + lineDigit;
          break;
        }
        y--;
        break;

      case KEY_DOWN:
        if(y >= gb->size - 2) break;
        else if(x == gapBufferAt(gb, y)->numOfChar + lineDigit || x >= gapBufferAt(gb, y+1)->numOfChar + lineDigit) {
          y++;
          x = gapBufferAt(gb, y)->numOfChar + lineDigit;
          break;
        }
          y++;
        break;

      case KEY_RIGHT:
        if(x >= gapBufferAt(gb, y)->numOfChar + lineDigit + 1) break;
        x++;
        break;

      case KEY_LEFT:
        if(x == lineDigit + 1) break;
        x--;
        break;

      case KEY_BACKSPACE:
        if(x <= lineDigit + 1) break;
        charArrayDel(gapBufferAt(gb, y), (x - lineDigit - 1));
        x--;
        move(y, x);
        delch();
        if(gapBufferAt(gb, y)->numOfChar == 0){
          gapBufferDel(gb, y, y+1);
          deleteln();
          lineNum--;
          move(y, 0);
          printStr(gb, lineDigit, y);
          if(y > 0) y -= 1;
          x = gapBufferAt(gb, y)->numOfChar + lineDigit ;
        }
        break;

      case 10:    // 10 is Enter key
      
        insertln();
        lineNum++;

        if(x == lineDigit + 1){

          {
            charArray* ca = (charArray*)malloc(sizeof(charArray));
            charArrayInit(ca);
            gapBufferInsert(gb, ca, y);
            charArrayPush(gapBufferAt(gb, y), '\0');
          }
          move(y, 0);
          printStr(gb, lineDigit, y);
          break;
        }else{
          {
            charArray* ca = (charArray*)malloc(sizeof(charArray));
            charArrayInit(ca);
            gapBufferInsert(gb, ca, y+1);
            charArrayPush(gapBufferAt(gb, y+1), '\0');
            memmove(gapBufferAt(gb, y+1)->elements, gapBufferAt(gb, y)->elements + (x - lineDigit -1), gapBufferAt(gb, y)->numOfChar - (x - lineDigit -1));
            for(int i=0; i < gapBufferAt(gb, y)->numOfChar - (x - lineDigit - 3); i++){
              charArrayPop(gapBufferAt(gb, y));
              gapBufferAt(gb, y)->numOfChar--;
              gapBufferAt(gb, y+1)->numOfChar++;
            }
          }
          move(y, 0);
          printStr(gb, lineDigit, y);
          break;
        }

      default:
        echo();
        charArrayInsert(gapBufferAt(gb, y), key, x - lineDigit - 1);
        insch(key);
        x++;
    }
  }
}

int openFile(char* filename){

  char  ch;

  int   lineNum = 0,
        lineDigit = 0;

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

  lineDigit = countLineDigit(lineNum);

  printStr(gb, lineDigit, 0);

  scrollok(stdscr, TRUE);			// enable scroll

  insertMode(gb, lineDigit, lineNum);

  return 0;
}

int main(int argc, char* argv[]){

  if(argc < 2){
    printf("cannot file open...\n");
    return -1;
  }

  openFile(argv[1]);

  return 0;
}
