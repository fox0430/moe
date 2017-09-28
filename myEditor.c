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

typedef struct editorStat{
  char filename[256];
  int   mode,
        lineDigit,
        lineDigitSpace,
        x,
        y,
        currentLine,
        numOfLines;
} editorStat;


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
void insertMode(gapBuffer* gb, editorStat* stat);
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

void editorStatInit(editorStat* stat){

//  stat->mode = 1;
  stat->currentLine = 0;
  stat->numOfLines = 0;
  stat->lineDigit = 3;    // 3 is default line digit
  stat->lineDigitSpace = stat->lineDigit + 1;
  stat->y = 0;
  stat->x = 0;
  strcpy(stat->filename, "text_new.txt");
}

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

  if(array->head > capacity || capacity <= 0){
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

int charArrayDel(charArray* array, int position){

  if(array->head == 0){
    printf("Vector: cannot pop from an empty array.");
    return -1;
  }

  memmove(array->elements + position - 1, array->elements + position, array->numOfChar - position);
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
    printf("Gapbuffer: New buffer capacity is too small.\n");
    return -1;
  }
  charArray** newBuffer = (charArray**)realloc(gb->buffer, sizeof(charArray*)*capacity);
  if(newBuffer == NULL){
    printf("Gapbuffer: Cannot reallocate new memory.\n");
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
    printf("Gapbuffer: Invalid position.\n");
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
    printf("Gapbuffer: Invalid position.\n");
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
    printf("Gapbuffer: Invalid interval.\n");
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
    printf("Gapbuffer: Invalid index.\n");
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

int countLineDigit(int numOfLines){

  int lineDigit = 0;
  while(numOfLines > 0){
    numOfLines /= 10;
    lineDigit++;
  }
  return lineDigit;
}

void printLineNum(int lineDigit, int currentLine, int y){

  int lineDigitSpace = lineDigit - countLineDigit(currentLine + 1);
  move(y, 0);
  for(int i=0; i<lineDigitSpace; i++) mvprintw(y, i, " ");
  bkgd(COLOR_PAIR(2));
  printw("%d:", currentLine + 1); 
}

void printStr(gapBuffer* gb, int lineDigit, int currentLine, int y){

  printLineNum(lineDigit, currentLine, y);
  bkgd(COLOR_PAIR(1));
  printw("%s", gapBufferAt(gb, currentLine)->elements);
}

void insertMode(gapBuffer* gb, editorStat* stat){

  int key;

  stat->y = 0;
  stat->x = stat->lineDigitSpace;
  stat->currentLine = 0;

  while(1){

    move(stat->y, stat->x);
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
        if(stat->currentLine == 0) break;
        
        if(stat->y == 0){
          stat->currentLine--;
          wscrl(stdscr, -1);    // scroll
          printStr(gb, stat->lineDigit,  stat->currentLine, stat->y);
          stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
          break;
        }else if(COLS - stat->lineDigitSpace - 1 <= gapBufferAt(gb, stat->currentLine - 1)->numOfChar){
          stat->y -= 2;
          stat->currentLine--;
          break;
        }

        stat->y--;
        stat->currentLine--;
        if(stat->x > stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1) stat->x = stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1;
        
        break;

      case KEY_DOWN:
        if(stat->currentLine + 1 == gb->size) break;
        
        if(stat->y >= LINES -1){
          stat->currentLine++;
          wscrl(stdscr, 1);
          move(LINES-1, 0);
          printStr(gb, stat->lineDigit, stat->currentLine, stat->y);
          stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace- 1;
          break;
        }else if(COLS - stat->lineDigitSpace - 1 <= gapBufferAt(gb, stat->currentLine + 1)->numOfChar){
          stat->y += 2;
          stat->currentLine++;
          break;
        }

        stat->y++;
        stat->currentLine++;
        if(stat->x > stat->lineDigitSpace + gapBufferAt(gb, stat->currentLine)->numOfChar) stat->x = stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1;
        
        break;
        
      case KEY_RIGHT:
        if(stat->x >= gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace) break;
        stat->x++;
        break;

      case KEY_LEFT:
        if(stat->x == stat->lineDigit + 1) break;
        stat->x--;
        break;
        
      case KEY_BACKSPACE:
        if(stat->y == 0 && stat->x == stat->lineDigitSpace) break;
        stat->x--;
        move(stat->y, stat->x);
        delch();
        // does not work...
        if(stat->x < stat->lineDigitSpace && gapBufferAt(gb, stat->currentLine)->numOfChar > 0) {
          for(int i=0; i<gapBufferAt(gb, stat->currentLine)->numOfChar; i++) {
            charArrayPush(gapBufferAt(gb, stat->currentLine - 1), gapBufferAt(gb, stat->currentLine)->elements[i]);
          }
          gapBufferDel(gb, stat->currentLine, stat->currentLine + 1);
          stat->numOfLines--;
          deleteln();
          move(stat->y - 1, stat->x);
          deleteln();
          insertln(); 
          for(int i=stat->y; i<stat->numOfLines; i++) {
            if(i == LINES - 1) break;
            printStr(gb, stat->lineDigit, i, i);
          }
        }
        charArrayDel(gapBufferAt(gb, stat->currentLine), (stat->x - stat->lineDigitSpace));
        if(stat->x < stat->lineDigitSpace && gapBufferAt(gb, stat->currentLine)->numOfChar == 0){
          gapBufferDel(gb, stat->currentLine, stat->currentLine + 1);
          deleteln();
          stat->numOfLines--;
          for(int i=stat->currentLine; i < gb->size-1; i++){
            if(i == LINES-1) break;
            printStr(gb, stat->lineDigit, i, i);
            printw("\n");
          }
          stat->currentLine--;
          if(stat->y > 0) stat->y--;
          stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace ;
        }
        break;

      case 10:    // 10 is Enter key
        stat->numOfLines++;
        if(stat->y == LINES - 1){
          stat->currentLine++;
          if(stat->x == stat->lineDigitSpace){
            {
              charArray* ca = (charArray*)malloc(sizeof(charArray));
              charArrayInit(ca);
              gapBufferInsert(gb, ca, stat->currentLine);
              charArrayPush(gapBufferAt(gb, stat->currentLine), '\0');
            }
          wscrl(stdscr, 1);
          printStr(gb, stat->lineDigit, stat->currentLine, LINES -1);
          stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
          }else{
            {
              charArray* ca = (charArray*)malloc(sizeof(charArray));
              charArrayInit(ca);
              gapBufferInsert(gb, ca, stat->currentLine + 1);
              charArrayPush(gapBufferAt(gb, stat->currentLine + 1), '\0');
              int tmp = gapBufferAt(gb, stat->currentLine)->numOfChar;
              for(int i = 0; i < tmp - (stat->x - stat->lineDigitSpace); i++){
                charArrayInsert(gapBufferAt(gb, stat->currentLine + 1), gapBufferAt(gb, stat->currentLine)->elements[i + stat->x - stat->lineDigitSpace], i);
                gapBufferAt(gb, stat->currentLine)->numOfChar--;
              }
            for(int i=0; i < tmp - (stat->x - stat->lineDigitSpace); i++) charArrayPop(gapBufferAt(gb, stat->currentLine));
            }
            // does not work...
            wscrl(stdscr, 1);
            printStr(gb, stat->lineDigit, stat->currentLine, LINES -1);
            stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
          }
          break;
        }

        insertln();
        if(stat->x == stat->lineDigitSpace){
          {
            charArray* ca = (charArray*)malloc(sizeof(charArray));
            charArrayInit(ca);
            gapBufferInsert(gb, ca, stat->currentLine);
            charArrayPush(gapBufferAt(gb, stat->currentLine), '\0');
            gapBufferAt(gb, stat->currentLine)->numOfChar++;
          }
          gapBufferAt(gb, stat->currentLine)->numOfChar--;
          for(int i=stat->currentLine; i < gb->size-1; i++){
            if(i == LINES-1) break;
            printStr(gb, stat->lineDigit, i, i);
            printw("\n");
          }
          stat->currentLine++;
          stat->y++;
          // Up lineDigit
          if(countLineDigit(stat->numOfLines) > countLineDigit(stat->numOfLines - 1)){
            stat->lineDigit = countLineDigit(stat->numOfLines);
            clear();
            for(int i=0; i<gb->size-1; i++){
              if(i == LINES-1) break;
              printStr(gb, stat->lineDigit, i, i);
              printw("\n");
            }
          }
          break;
        }else{
          {
            charArray* ca = (charArray*)malloc(sizeof(charArray));
            charArrayInit(ca);
            gapBufferInsert(gb, ca, stat->currentLine + 1);
            charArrayPush(gapBufferAt(gb, stat->currentLine + 1), '\0');
            int tmp = gapBufferAt(gb, stat->currentLine)->numOfChar;
            for(int i = 0; i < tmp - (stat->x - stat->lineDigitSpace); i++){
              charArrayInsert(gapBufferAt(gb, stat->currentLine + 1), gapBufferAt(gb, stat->currentLine)->elements[i + stat->x - stat->lineDigitSpace], i);
              gapBufferAt(gb, stat->currentLine)->numOfChar--;
            }
            for(int i=0; i < tmp - (stat->x - stat->lineDigitSpace); i++) charArrayPop(gapBufferAt(gb, stat->currentLine));
          }
          stat->x = stat->lineDigitSpace;
          for(int i=stat->currentLine; i < gb->size-1; i++){
            if(i == LINES-1) break;
            printStr(gb, stat->lineDigit, i, i);
            printw("\n");
          }
          stat->currentLine++;
          stat->y++;
          // Up lineDigit
          if(countLineDigit(stat->numOfLines) > countLineDigit(stat->numOfLines - 1)){
            stat->lineDigit = countLineDigit(stat->numOfLines);
            clear();
            for(int i=0; i<gb->size-1; i++){
              if(i == LINES-1) break;
              printStr(gb, stat->lineDigit, i, i);
              printw("\n");
            }
          }
          break;
        }

      default:
        echo();
        charArrayInsert(gapBufferAt(gb, stat->currentLine), key, stat->x - stat->lineDigitSpace);
        insch(key);
        stat->x++;
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

  editorStat* stat = (editorStat*)malloc(sizeof(editorStat));
  editorStatInit(stat);

  char  ch;
  while((ch = fgetc(fp)) != EOF){
    if(ch=='\n'){
      stat->currentLine += 1;
      charArray* ca = (charArray*)malloc(sizeof(charArray));
      charArrayInit(ca);
      gapBufferInsert(gb, ca, stat->currentLine);
    }else charArrayPush(gapBufferAt(gb, stat->currentLine), ch);
  }
  fclose(fp);

  startCurses();

  if(stat->lineDigit < countLineDigit(stat->currentLine + 1)) stat->lineDigit = countLineDigit(stat->currentLine + 1);

  stat->numOfLines = stat->currentLine + 1;
  for(int i=0; i < stat->numOfLines; i++){
    if(i == LINES) break;
    printStr(gb, stat->lineDigit, i, i);
    printw("\n");
  }

  scrollok(stdscr, TRUE);			// enable scroll
  insertMode(gb, stat);

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

  editorStat* stat = (editorStat*)malloc(sizeof(editorStat));
  editorStatInit(stat);


  startCurses(); 
  printStr(gb, stat->lineDigit, 0, 0);
  scrollok(stdscr, TRUE);			// enable scroll
  insertMode(gb, stat);

  return 0;
}

int main(int argc, char* argv[]){

  if(argc < 2){
    newFile();
  }

  openFile(argv[1]);

  return 0;
}
