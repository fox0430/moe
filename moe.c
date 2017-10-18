#include"moe.h"

void debugMode(WINDOW **win, gapBuffer *gb, editorStat *stat){
  
  wclear(win[2]);
  wprintw(win[2], "currentLine: %d", stat->currentLine);
}

void **winInit(WINDOW **win){
 win[0] = newwin(LINES-2, COLS, 0, 0);    // main window
 win[1] = newwin(1, COLS, LINES-2, 0);    // status bar
 win[2] = newwin(1, COLS, LINES-1, 0);    // command bar
 win[3] = newwin(LINES-2, 4, 0, 0);       // line number
}

void startCurses(){

  int h,
      w;

  initscr();    // start terminal contorl
  cbreak();   // enable cbreak mode
  curs_set(1);    // set cursr

  getmaxyx(stdscr, h, w);     // set window size

  start_color();      // color settings
  init_pair(1, COLOR_WHITE, COLOR_CYAN);    // char is while, bg is CYAN
  init_pair(2, COLOR_BLACK, COLOR_WHITE);

  erase();  	// screen display

//  setlocale(LC_ALL, "");

  ESCDELAY = 25;    // delete esc key time lag
}

void signal_handler(int SIG){
  endwin();
  exit(1);
}

void exitCurses(){
 endwin(); 
 exit(1);
}

void editorStatInit(editorStat* stat){

  stat->mode = 0;   // 0 is normal mode
  stat->currentLine = 0;
  stat->numOfLines = 0;
  stat->lineDigit = 3;    // 3 is default line digit
  stat->lineDigitSpace = stat->lineDigit + 1;
  stat->y = 0;
  stat->x = 0;
  strcpy(stat->filename, "test.txt");
}

int writeFile(WINDOW **win, gapBuffer* gb, editorStat *stat){
  
  FILE *fp;

  if ((fp = fopen(stat->filename, "w")) == NULL) {
    printf("%s Cannot file open... \n", stat->filename);
      return -1;
    }
  
  for(int i=0; i < gb->size; i++){
    fputs(gapBufferAt(gb, i)->elements, fp);
    if(i != gb->size) fputc('\n', fp);
  }

  mvwprintw(win[2], 0, 0, "%s", "saved...");
  wrefresh(win[2]);

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

void printLineNum(WINDOW **win, editorStat *stat, int startLine){

  for(int i=0; i<LINES-2; i++){
    if(i == stat->numOfLines) break;
    int lineDigitSpace = stat->lineDigit - countLineDigit(startLine + 1);
    for(int j=0; j<lineDigitSpace; j++) mvwprintw(win[3], i, j, " ");
    wprintw(win[3], "%d:", ++startLine);
    wrefresh(win[3]);
  }
}

void printLine(WINDOW **win, gapBuffer* gb, int lineDigit, int currentLine, int y){
  
  use_default_colors();
  mvwprintw(win[0], y, lineDigit + 1, "%s", gapBufferAt(gb, currentLine)->elements);
  wrefresh(win[0]);
}

void commandBar(WINDOW **win, gapBuffer *gb, editorStat *stat){
  werase(win[2]);
  wprintw(win[2], "%s", ":");
  wrefresh(win[2]);
  nocbreak();
  echo();

  int key;
  key = wgetch(win[2]);
  noecho();

  switch(key){
    case 'w':
      writeFile(win, gb, stat);
      break;
    case 'q':
      exitCurses();
      break;
  }
  cbreak();
  normalMode(win, gb, stat);
}

void printStatBarInit(WINDOW **win, editorStat *stat){
  wclear(win[1]);

  wbkgd(win[1], COLOR_PAIR(2));
  if(stat->mode == 0){
    wprintw(win[1], "%s ", "normal");
  }else if(stat->mode == 1){
    wprintw(win[1], "%s ", "insert");
  }

  wbkgd(win[1], COLOR_PAIR(1));
  wprintw(win[1], "%s ", stat->filename);
  printStatBar(win, stat);
}

void printStatBar(WINDOW **win, editorStat *stat){
  mvwprintw(win[1], 0, COLS-7, "%d/%d ", stat->currentLine + 1, stat->numOfLines);
  mvwprintw(win[1], 0, COLS-3, " %d", stat->x - stat->lineDigitSpace + 1);
  wrefresh(win[1]);
}

int insNewLine(gapBuffer *gb, int position){
    charArray* ca = (charArray*)malloc(sizeof(charArray));
    charArrayInit(ca);
    gapBufferInsert(gb, ca, position);
    return 0;
}

int keyUp(WINDOW **win, gapBuffer* gb, editorStat* stat){
  if(stat->currentLine == 0) return 0;
        
  if(stat->y == 0){
    stat->currentLine--;
    wscrl(win[0], -1);    // scroll
    printLine(win, gb, stat->lineDigit,  stat->currentLine, stat->y);
    printLineNum(win, stat, stat->currentLine);
    stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
    return 0;
  }else if(COLS - stat->lineDigitSpace - 1 <= gapBufferAt(gb, stat->currentLine - 1)->numOfChar){
    stat->y -= 2;
    stat->currentLine--;
    return 0;
  }

  stat->y--;
  stat->currentLine--;
  if(stat->x > stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1)
    stat->x = stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1;
  return 0;
}

int keyDown(WINDOW **win, gapBuffer* gb, editorStat* stat){
  if(stat->currentLine + 1 == gb->size) return 0;
        
  if(stat->y == LINES - 3){
    stat->currentLine++;
    wscrl(win[0], 1);
    wmove(win[0], LINES - 3, 0);
    printLine(win, gb, stat->lineDigit, stat->currentLine, LINES - 3);
    printLineNum(win, stat, stat->currentLine - LINES + 3);
    stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;

    return 0;
  }else if(COLS - stat->lineDigitSpace - 1 <= gapBufferAt(gb, stat->currentLine + 1)->numOfChar){
    stat->y += 2;
    stat->currentLine++;
    return 0;
  }
  stat->y++;
  stat->currentLine++;
  if(stat->x > stat->lineDigitSpace + gapBufferAt(gb, stat->currentLine)->numOfChar)
    stat->x = stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1;
  return 0;
}

int keyRight(gapBuffer* gb, editorStat* stat){

  if(stat->x >= gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace) return 0;
  stat->x++;
  return 0;
}

int keyLeft(gapBuffer* gb, editorStat* stat){

  if(stat->x == stat->lineDigit + 1) return 0;
  stat->x--;
  return 0;
}

int keyBackSpace(WINDOW **win, gapBuffer* gb, editorStat* stat){
  if(stat->y == 0 && stat->x == stat->lineDigitSpace) return 0;
  mvwdelch(win[0], stat->y, --stat->x);
  if(stat->x < stat->lineDigitSpace && gapBufferAt(gb, stat->currentLine)->numOfChar > 0){    // delete line
    int tmpNumOfChar = gapBufferAt(gb, stat->currentLine - 1)->numOfChar;
    for(int i=0; i<gapBufferAt(gb, stat->currentLine)->numOfChar; i++) {
      charArrayPush(gapBufferAt(gb, stat->currentLine - 1), gapBufferAt(gb, stat->currentLine)->elements[i]);
    }
    gapBufferDel(gb, stat->currentLine, stat->currentLine + 1);
    stat->numOfLines--;
    wdeleteln(win[0]);
    wmove(win[0], stat->y - 1, stat->x);
    for(int i=stat->y - 1; i<stat->numOfLines; i++){
      if(i == LINES - 3) break;
      printLine(win, gb, stat->lineDigit, i, i);
    }
    stat->y--;
    stat->x = stat->lineDigitSpace + tmpNumOfChar;
    stat->currentLine--;
    printLineNum(win, stat, stat->currentLine - stat->y);
    return 0;
  }

  charArrayDel(gapBufferAt(gb, stat->currentLine), (stat->x - stat->lineDigitSpace));
  if(stat->x < stat->lineDigitSpace && gapBufferAt(gb, stat->currentLine)->numOfChar == 0){
    gapBufferDel(gb, stat->currentLine, stat->currentLine + 1);
    wdeleteln(win[0]);
    stat->numOfLines--;
    for(int i=stat->currentLine; i < gb->size; i++){
      if(i == LINES-3) return 0;
        printLine(win, gb, stat->lineDigit, i, i);
        wprintw(win[0], "\n");
      }
    stat->currentLine--;
    if(stat->y > 0) stat->y--;
    stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace ;
  }
  return 0;
}

int keyEnter(WINDOW **win, gapBuffer* gb, editorStat* stat){
  stat->numOfLines++;
  if(stat->y == LINES - 3){
    stat->currentLine++;
    if(stat->x == stat->lineDigitSpace){
      insNewLine(gb, stat->currentLine);
      charArrayPush(gapBufferAt(gb, stat->currentLine), '\0');
      wscrl(win[0], 1);
      printLine(win, gb, stat->lineDigit, stat->currentLine, LINES -3);
      printLineNum(win, stat, stat->currentLine - stat->y);
      stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
    }else{
      insNewLine(gb, stat->currentLine + 1);
      charArrayPush(gapBufferAt(gb, stat->currentLine + 1), '\0');
      int tmp = gapBufferAt(gb, stat->currentLine)->numOfChar;
      for(int i = 0; i < tmp - (stat->x - stat->lineDigitSpace); i++){
        charArrayInsert(gapBufferAt(gb, stat->currentLine + 1), gapBufferAt(gb, stat->currentLine)->elements[i + stat->x - stat->lineDigitSpace], i);
        gapBufferAt(gb, stat->currentLine)->numOfChar--;
        for(int i=0; i < tmp - (stat->x - stat->lineDigitSpace); i++) charArrayPop(gapBufferAt(gb, stat->currentLine - 1));
      }
      wscrl(win[0], 1);
      wmove(win[0], LINES - 2, stat->x);
      wdeleteln(win[0]);
      for(int i=0; i<LINES-2; i++){
        printLine(win, gb, stat->lineDigit, stat->currentLine - stat->y + i, i);
      }
      stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
      stat->currentLine++;
      printLineNum(win, stat, stat->currentLine - stat->y);
    }
    return 0;
  }

  winsertln(win[0]);
  if(stat->x == stat->lineDigitSpace){    // beginning of line
    insNewLine(gb, stat->currentLine);
    charArrayPush(gapBufferAt(gb, stat->currentLine), '\0');
    gapBufferAt(gb, stat->currentLine)->numOfChar++;
    gapBufferAt(gb, stat->currentLine)->numOfChar--;
    for(int i=stat->currentLine; i < gb->size; i++){
      if(i == LINES - 3) break;
        printLine(win, gb, stat->lineDigit, i, i);
        wprintw(win[0], "\n");
    }
    stat->currentLine++;
    stat->y++;
    // Up lineDigit
    if(countLineDigit(stat->numOfLines) > countLineDigit(stat->numOfLines - 1)){
      stat->lineDigit = countLineDigit(stat->numOfLines);
      wclear(win[0]);
      for(int i=0; i<gb->size; i++){
        if(i == LINES - 3) break;
          printLine(win, gb, stat->lineDigit, i, i);
          wprintw(win[0], "\n");
      }
    }
    printLineNum(win, stat, stat->currentLine - stat->y);
    return 0;
  }else{
    insNewLine(gb, stat->currentLine + 1);
    charArrayPush(gapBufferAt(gb, stat->currentLine + 1), '\0');
    int tmp = gapBufferAt(gb, stat->currentLine)->numOfChar;
    for(int i = 0; i < tmp - (stat->x - stat->lineDigitSpace); i++){
      charArrayInsert(gapBufferAt(gb, stat->currentLine + 1), gapBufferAt(gb, stat->currentLine)->elements[i + stat->x - stat->lineDigitSpace], i);
      gapBufferAt(gb, stat->currentLine)->numOfChar--;
      for(int i=0; i < tmp - (stat->x - stat->lineDigitSpace); i++) charArrayPop(gapBufferAt(gb, stat->currentLine));
    }
    stat->x = stat->lineDigitSpace;
    for(int i=stat->currentLine; i < gb->size; i++){
      if(i == LINES - 3) break;
        printLine(win, gb, stat->lineDigit, i, i);
        wprintw(win[0], "\n");
    }
    stat->currentLine++;
    stat->y++;
    // Up lineDigit
    if(countLineDigit(stat->numOfLines) > countLineDigit(stat->numOfLines - 1)){
      stat->lineDigit = countLineDigit(stat->numOfLines);
      wclear(win[0]);
      for(int i=0; i<gb->size; i++){
        if(i == LINES - 3) break;
          printLine(win, gb, stat->lineDigit, i, i);
          wprintw(win[0], "\n");
      }
    }
    printLineNum(win, stat, stat->currentLine - stat->y);
    return 0;
  }
}

int keyX(WINDOW **win, gapBuffer *gb, editorStat *stat){
  wdelch(win[0]);
  charArrayDel(gapBufferAt(gb, stat->currentLine), (stat->x - stat->lineDigitSpace));
  return 0;
}

void normalMode(WINDOW **win, gapBuffer *gb, editorStat *stat){

  int key;
  stat->mode = 0;
  printStatBarInit(win, stat);

  while(1){
    wmove(win[0], stat->y, stat->x);
    printStatBar(win, stat); 
    wrefresh(win[0]);
    noecho();
    key = wgetch(win[0]);

    switch(key){
      case 'h':
        keyLeft(gb, stat);
        break;
      case 'j':
        keyDown(win, gb, stat);
       break;
      case 'k':
        keyUp(win, gb, stat);
        break;
      case 'l':
        keyRight(gb, stat);
        break;
      case 'x':
        keyX(win, gb, stat);
        break;
      case '0':
        stat->x = stat->lineDigitSpace;
        break;
      case '$':
        stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
        break;
      case 'a':
        wmove(win[0], stat->y, stat->x++);
        insertMode(win, gb, stat);
        break;

      case 'i':
        insertMode(win, gb, stat);
        break;
      case ':':
        commandBar(win, gb, stat);
        break;

      case KEY_ESC:   // get arrow keys but has problem...
        wgetch(win[0]);   // skip the '['
        switch(wgetch(win[0])){
          case 'A':
            keyUp(win, gb, stat);
            break;
          case 'B':
            keyDown(win, gb, stat);
            break;
          case 'C':
            keyRight(gb, stat);
            break;
          case 'D':
            keyLeft(gb, stat);
            break;
        }
    }
  }
}

void insertMode(WINDOW **win, gapBuffer* gb, editorStat* stat){

  int key;
  stat->mode = 1;
  printStatBarInit(win, stat);
  wclear(win[2]);
  wrefresh(win[2]);

  while(1){

    wmove(win[0], stat->y, stat->x);
    printStatBar(win, stat);
    noecho();
    key = wgetch(win[0]);

    if(key == KEY_ESC){
      normalMode(win, gb, stat);
      break;
    } 

    switch(key){
/*

arrow keys does not work...

      case KEY_UP:
        keyUp(win, gb, stat);
        break;

      case KEY_DOWN:
        keyDown(win, gb, stat);
        break;
        
      case KEY_RIGHT:
        keyRight(gb, stat);
        break;

      case KEY_LEFT:
        keyLeft(gb, stat);
        break;
*/        
      case 127:   // 127 is backspace key
        keyBackSpace(win, gb, stat);
        break;

      case 10:    // 10 is Enter key
        keyEnter(win, gb, stat);
        break;
      
      default:
        echo();
        charArrayInsert(gapBufferAt(gb, stat->currentLine), key, stat->x - stat->lineDigitSpace);
        winsch(win[0], key);
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
  insNewLine(gb, 0);
  editorStat* stat = (editorStat*)malloc(sizeof(editorStat));
  editorStatInit(stat);
  strcpy(stat->filename, filename);

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

  WINDOW **win = (WINDOW**)malloc(sizeof(WINDOW*)*4);
  if(signal(SIGINT, signal_handler) == SIG_ERR ||
     signal(SIGQUIT, signal_handler) == SIG_ERR){
    fprintf(stderr, "signal failure\n");
    exit(EXIT_FAILURE);
  }

  if(initscr() == NULL){
    fprintf(stderr, "initscr failure\n");
    exit(EXIT_FAILURE);
  }

  startCurses();
  winInit(win);

  if(stat->lineDigit < countLineDigit(stat->currentLine + 1)) stat->lineDigit = countLineDigit(stat->currentLine + 1);

  stat->numOfLines = stat->currentLine + 1;
  for(int i=0; i < stat->numOfLines; i++){
    if(i == LINES - 2) break;
    printLine(win, gb, stat->lineDigit, i, i);
    wprintw(win[0], "\n");
  }

  scrollok(win[0], TRUE);			// enable scroll

  stat->x = stat->lineDigitSpace;
  stat->currentLine = 0;

  printLineNum(win, stat, 0);
  normalMode(win, gb, stat);

  return 0;
}

int newFile(){

  gapBuffer* gb = (gapBuffer*)malloc(sizeof(gapBuffer));
  gapBufferInit(gb);
  insNewLine(gb, 0);

  editorStat* stat = (editorStat*)malloc(sizeof(editorStat));
  editorStatInit(stat);

  WINDOW **win = (WINDOW**)malloc(sizeof(WINDOW*)*4);
  winInit(win);

  startCurses(); 
  keypad(win[0], TRUE);   // enable cursr keys
  printLine(win, gb, stat->lineDigit, 0, 0);
  scrollok(stdscr, TRUE);			// enable scroll
  insertMode(win, gb, stat);

  return 0;
}

int main(int argc, char* argv[]){

  if(argc < 2){
    newFile();
  }

  openFile(argv[1]);

  return 0;
}
