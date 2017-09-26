#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<stdbool.h>
#include<assert.h>
#include<malloc.h>
#include<ncurses.h>
//#include<locale.h>


#define KEY_ESC 27
//#define WIN_NUM 2


// Vector
typedef struct charArray{
  char* elements;
  int   capacity,
        head,
        numOfChar;
} charArray;

// Gapbuffer
typedef struct gapBuffer{
  struct  charArray** buffer;
  int     size,       // 意味のあるデータが実際に格納されているサイズ
          capacity,   // Amount of secured memory
          gapBegin,
          gapEnd;     // 半開区間[gap_begin,gap_end)を隙間とする
} gapBuffer;

/*
typedef struct editorStat{
  char filename[256];
  int   mode,
        lineDigit,
        lineDigitSpace,
        x,
        y,
        line;
} editorStat;
*/


// Function prototype
void startCurses();
void exitCurses();
int charArrayInit(charArray* array);
int charArrayReserve(charArray* array, int capacity);
int charArrayPush(charArray* array, char element);
int charArrayInsert(charArray* array, char element, int position);
int charArrayPop(charArray* array);
int charArrayDel(charArray* array, int position);
bool charArrayIsEmpty(charArray* array);
int gapBufferReserve(gapBuffer* gb, int capacity);
int gapBufferMakeGap(gapBuffer* gb,int gapBegin);
int gapBufferInsert(gapBuffer* gb, charArray* element, int position);
int gapBufferDel(gapBuffer* gb, int begin, int end);
charArray* gapBufferAt(gapBuffer* gb, int index);
bool gapBufferIsEmpty(gapBuffer* gb);
int writeFile(gapBuffer* gb);
int countLineDigit(int lineNum);
void printLineNum(int lineDigit, int line, int y);
void printStr(gapBuffer* gb, int lineDigit, int line, int y);
//void insertMode(gapBuffer* gb, int lineDigit, int lineNum, editorStat* stat);
void insertMode(gapBuffer* gb, int lineDigit, int lineNum);
int newFile();
int openFile(char* filename);


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

//  setlocale(LC_ALL, "");

  ESCDELAY = 25;    // delete esc key time lag

/*
  WINDOW *windows[WIN_NUM];
  if(signal(SIGINT, signal_handler) == SIG_ERR ||
    signal(SIGQUIT, signal_handler) == SIG_ERR){
      fprintf(stderr, "signal failure\n");
      exit(EXIT_FAILURE);
  }

  if(initscr() == NULL){
    fprintf(stderr, "initscr failure\n");
    exit(EXIT_FAILURE);
  }
*/

  move(0, 0);     // set cursr point
}

void exitCurses(){
 endwin(); 
}

/*
void editorStatInit(editorStat* stat){

  stat->mode = 1;
  stat->line = 0;
  stat->lineDigit = 3;    // 3 is default line digit
  stat->lineDigitSpace = stat->lineDigit + 1;
  stat->y = 0;
  stat->x = 0;
  strcpy(stat->filename, "text_new.txt");
}
*/

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
  array->numOfChar = 0;
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

  --array->numOfChar;

  if(array->head*4 <= array->capacity){
    char* newElements = (char*)realloc(array->elements, sizeof(char)*(array->capacity / 2 + 1));
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

  if(position < 0 || array->head <= position){
    printf("delete position is out of range.");
    return -1;
  }

  memmove(array->elements + position, array->elements + position + 1, sizeof(char) * (array->head - (position + 1)));
  charArrayPop(array);

  if(array->head*4 <= array->capacity){
    char* newElements = (char*)realloc(array->elements, sizeof(char)*(array->capacity / 2 + 1));
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

void printLineNum(int lineDigit, int line, int y){

  int lineDigitSpace = lineDigit - countLineDigit(line + 1);
  move(y, 0);
  for(int i=0; i<lineDigitSpace; i++) mvprintw(y, i, " ");
  bkgd(COLOR_PAIR(2));
  printw("%d:", line + 1); 
}

void printStr(gapBuffer* gb, int lineDigit, int line, int y){

  printLineNum(lineDigit, line, y);
  bkgd(COLOR_PAIR(1));
  printw("%s", gapBufferAt(gb, line)->elements);
}

//void insertMode(gapBuffer* gb, int lineDigit, int lineNum, editorStat* stat){
void insertMode(gapBuffer* gb, int lineDigit, int lineNum){

  int key,
      lineDigitSpace = lineDigit + 1,
      y     = 0,
      x     = lineDigitSpace,
      line  = 0;    // gapBuffer position

  while(1){

    move(y, x);
    refresh();
    noecho();
    key = getch();

    if(key == KEY_ESC){
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
        if(line == 0) break;
        
        if(y == 0){
          line--;
          wscrl(stdscr, -1);    // scroll
          printStr(gb, lineDigit, line, y);
          x = gapBufferAt(gb, line)->numOfChar + lineDigitSpace - 1;
          break;
        }else if(COLS - lineDigitSpace - 1 <= gapBufferAt(gb, line-1)->numOfChar){
          y -= 2;
          line--;
          break;
        }

        y--;
        line--;
        if(x > lineDigit + gapBufferAt(gb, line)->numOfChar + 1) x = lineDigit + gapBufferAt(gb, line)->numOfChar + 1;
        
        break;

      case KEY_DOWN:
        if(line + 1 == gb->size) break;
        
        if(y >= LINES -1){
          line++;
          wscrl(stdscr, 1);
          move(LINES-1, 0);
          printStr(gb, lineDigit, line, y);
          x = gapBufferAt(gb, line)->numOfChar + lineDigitSpace - 1;
          break;
        }else if(COLS - lineDigitSpace - 1 <= gapBufferAt(gb, line+1)->numOfChar){
          y += 2;
          line++;
          break;
        }

        y++;
        line++;
        if(x > lineDigit + gapBufferAt(gb, line)->numOfChar + 1) x = lineDigit + gapBufferAt(gb, line)->numOfChar + 1;
        
        break;
        
      case KEY_RIGHT:
        if(x >= gapBufferAt(gb, line)->numOfChar + lineDigitSpace) break;
        x++;
        break;

      case KEY_LEFT:
        if(x == lineDigit + 1) break;
        x--;
        break;
        
      case KEY_BACKSPACE:
        if(x == lineDigitSpace && gapBufferAt(gb, line)->numOfChar != 0) break;
        charArrayDel(gapBufferAt(gb, line), (x - lineDigitSpace));
        x--;
        move(y, x);
        delch();
        if(x <= lineDigitSpace && gapBufferAt(gb, line)->numOfChar == 0){
          gapBufferDel(gb, line, line+1);
          deleteln();
          lineNum--;
          for(int i=line; i < gb->size-1; i++){
            if(i == LINES-1) break;
            printStr(gb, lineDigit, i, i);
            printw("\n");
          }
          line--;
          if(y > 0) y -= 1;
          x = gapBufferAt(gb, line)->numOfChar + lineDigitSpace ;
        }
        break;

      case 10:    // 10 is Enter key
        lineNum++;
        if(y == LINES - 1){
          line++;
          if(x == lineDigitSpace){
            {
              charArray* ca = (charArray*)malloc(sizeof(charArray));
              charArrayInit(ca);
              gapBufferInsert(gb, ca, line);
              charArrayPush(gapBufferAt(gb, line), '\0');
            }
          wscrl(stdscr, 1);
          printStr(gb, lineDigit, line, LINES -1);
          x = gapBufferAt(gb, line)->numOfChar + lineDigitSpace - 1;
          }else{
            {
              charArray* ca = (charArray*)malloc(sizeof(charArray));
              charArrayInit(ca);
              gapBufferInsert(gb, ca, line+1);
              charArrayPush(gapBufferAt(gb, line+1), '\0');
              int tmp = gapBufferAt(gb, line)->numOfChar;
              for(int i = 0; i < tmp - (x - lineDigitSpace); i++){
                charArrayInsert(gapBufferAt(gb, line+1), gapBufferAt(gb, line)->elements[i + x - lineDigitSpace], i);
                gapBufferAt(gb, line)->numOfChar--;
              }
            for(int i=0; i < tmp - (x - lineDigitSpace); i++) charArrayPop(gapBufferAt(gb, line));
            }
            // does not work...
            wscrl(stdscr, 1);
            printStr(gb, lineDigit, line, LINES -1);
            x = gapBufferAt(gb, line)->numOfChar + lineDigitSpace - 1;
          }
          break;
        }

        insertln();
        if(x == lineDigitSpace){
          {
            charArray* ca = (charArray*)malloc(sizeof(charArray));
            charArrayInit(ca);
            gapBufferInsert(gb, ca, line);
            charArrayPush(gapBufferAt(gb, line), '\0');
            gapBufferAt(gb, line)->numOfChar++;
          }
          gapBufferAt(gb, line)->numOfChar--;
          for(int i=line; i < gb->size-1; i++){
            if(i == LINES-1) break;
            printStr(gb, lineDigit, i, i);
            printw("\n");
          }
          line++;
          y++;
          // Up lineDigit
          if(countLineDigit(lineNum) > countLineDigit(lineNum - 1)){
            lineDigit = countLineDigit(lineNum);
            clear();
            for(int i=0; i<gb->size-1; i++){
              if(i == LINES-1) break;
              printStr(gb, lineDigit, i, i);
              printw("\n");
            }
          }
          break;
        }else{
          {
            charArray* ca = (charArray*)malloc(sizeof(charArray));
            charArrayInit(ca);
            gapBufferInsert(gb, ca, line+1);
            charArrayPush(gapBufferAt(gb, line+1), '\0');
            int tmp = gapBufferAt(gb, line)->numOfChar;
            for(int i = 0; i < tmp - (x - lineDigitSpace); i++){
              charArrayInsert(gapBufferAt(gb, line+1), gapBufferAt(gb, line)->elements[i + x - lineDigitSpace], i);
              gapBufferAt(gb, line)->numOfChar--;
            }
            for(int i=0; i < tmp - (x - lineDigitSpace); i++) charArrayPop(gapBufferAt(gb, line));
          }
          x = lineDigitSpace;
          for(int i=line; i < gb->size-1; i++){
            if(i == LINES-1) break;
            printStr(gb, lineDigit, i, i);
            printw("\n");
          }
          line++;
          y++;
          // Up lineDigit
          if(countLineDigit(lineNum) > countLineDigit(lineNum - 1)){
            lineDigit = countLineDigit(lineNum);
            clear();
            for(int i=0; i<gb->size-1; i++){
              if(i == LINES-1) break;
              printStr(gb, lineDigit, i, i);
              printw("\n");
            }
          }
          break;
        }

      default:
        echo();
        charArrayInsert(gapBufferAt(gb, line), key, x - lineDigitSpace);
        insch(key);
        x++;
    }
  }
}

int openFile(char* filename){

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

  int   currentLine = 0;
  char  ch;
  while((ch = fgetc(fp)) != EOF){
    if(ch=='\n'){
      ++currentLine;
      charArray* ca = (charArray*)malloc(sizeof(charArray));
      charArrayInit(ca);
      gapBufferInsert(gb, ca, currentLine);
    }else charArrayPush(gapBufferAt(gb, currentLine), ch);
  }
  fclose(fp);

  startCurses();

/*
  editorStat* stat = (editorStat*)malloc(sizeof(editorStat));
  editorStatInit(stat);
*/

  int lineDigit = 3;    // 3 is default line digit space

  if(lineDigit < countLineDigit(currentLine + 1)) lineDigit = countLineDigit(currentLine + 1);

  const int numOfLines = currentLine + 1;
  for(int i=0; i < numOfLines - 1; i++){
    if(i == LINES) break;
    printStr(gb, lineDigit, i, i);
    printw("\n");
  }

  scrollok(stdscr, TRUE);			// enable scroll

//  insertMode(gb, lineDigit, numOfLines, stat);
  insertMode(gb, lineDigit, numOfLines);

  return 0;
}

int newFile(){

  gapBuffer* gb = (gapBuffer*)malloc(sizeof(gapBuffer));
  gapBufferInit(gb);
  {
    charArray* ca = (charArray*)malloc(sizeof(charArray));
    charArrayInit(ca);
    gapBufferInsert(gb, ca, 0);
  }

/*
  editorStat* stat = (editorStat*)malloc(sizeof(editorStat));
  editorStatInit(stat);
*/

  int lineDigit = 1,
      lineNum = 1;

  startCurses(); 
  printStr(gb, lineDigit, 0, 0);
  scrollok(stdscr, TRUE);			// enable scroll
//  insertMode(gb, lineDigit, lineNum, stat);
  insertMode(gb, lineDigit, lineNum);

  return 0;
}

int main(int argc, char* argv[]){

  if(argc < 2){
    newFile();
  }

  openFile(argv[1]);

  return 0;
}
