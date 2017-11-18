#include"moe.h"

int debugMode(WINDOW **win, gapBuffer *gb, editorStat *stat){
  stat->debugMode = ON;
  if(stat->debugMode == OFF ) return 0;
  werase(win[2]);
  mvwprintw(win[2], 0, 0, "debug mode: ");
  wprintw(win[2], "currentLine: %d ", stat->currentLine);
  wprintw(win[2], "numOfLines: %d ", stat->numOfLines);
  wprintw(win[2], "numOfChar: %d ", gapBufferAt(gb, stat->currentLine)->numOfChar);
  wprintw(win[2], "ture: %d ", stat->trueLine[stat->currentLine]);
  wprintw(win[2], "elements: %s", gapBufferAt(gb, stat->currentLine)->elements);
  wrefresh(win[2]);
  wmove(win[0], stat->y, stat->x);
  return 0;
}

void winInit(WINDOW **win){
  win[0] = newwin(LINES-2, COLS, 0, 0);    // main window
  win[1] = newwin(1, COLS, LINES-2, 0);    // status bar
  win[2] = newwin(1, COLS, LINES-1, 0);    // command bar
  keypad(win[0], TRUE);   // enable function key
  keypad(win[2], TRUE);
  scrollok(win[0], TRUE);			// enable scroll
}

void winResizeMove(WINDOW *win, int lines, int columns, int y, int x){
  wresize(win, lines, columns);
  mvwin(win, y, x);
}

int setCursesColor(){
  bool color_check = can_change_color();
  if(color_check != TRUE) return 0;

  start_color();      // color settings

  use_default_colors();   // terminal default color

  init_pair(1, COLOR_BLACK , COLOR_GREEN);    // char is black, bg is green
  init_pair(2, COLOR_BLACK, BRIGHT_WHITE);
  init_pair(3, GRAY, COLOR_DEFAULT);
  init_pair(4, COLOR_RED, COLOR_DEFAULT);
  init_pair(5, COLOR_GREEN, COLOR_BLACK);
  init_pair(6, BRIGHT_WHITE, COLOR_DEFAULT);
  init_pair(7, BRIGHT_GREEN, COLOR_DEFAULT);
  return 0;
}

void startCurses(){
  initscr();    // start terminal contorl
  cbreak();   // enable cbreak mode
  curs_set(1);    // set cursr

  setCursesColor();
  erase();

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

void winResizeEvent(WINDOW **win, gapBuffer *gb, editorStat *stat){
  endwin(); 
  initscr();
  winResizeMove(win[0], LINES-2, COLS, 0, 0);
  winResizeMove(win[1], 1, COLS, LINES-2, 0);
  winResizeMove(win[2], 1, COLS, LINES-1, 0);
  printLineAll(win, gb, stat);
  printStatBarInit(win, gb, stat);
}

void editorStatInit(editorStat* stat){
  stat->y = 0;
  stat->x = 0;
  stat->currentLine = 0;
  stat->numOfLines = 0;
  stat->lineDigit = 3;    // 3 is default line digit
  stat->lineDigitSpace = stat->lineDigit + 1;
  stat->mode = NORMAL_MODE;
  stat->cmdLoop = 0;
  strcpy(stat->filename, "No name");
  stat->numOfChange = 0;
  stat->currentLine = false;
  stat->debugMode = OFF;
  trueLineInit(stat);
  registersInit(stat);
}

int trueLineInit(editorStat *stat){
  stat->trueLineCapa = 1000;
  stat->trueLine = (int*)malloc(sizeof(int)*stat->trueLineCapa);
  if(stat->trueLine == NULL){
      printf("main trueLine: cannot allocate memory...\n");
      return -1;
  }
  for(int i=0; i<stat->trueLineCapa; i++)
    stat->trueLine[i] = true;
  return 0;
}

void registersInit(editorStat *stat){
  stat->rgst.yankedLine = (gapBuffer*)malloc(sizeof(gapBuffer));
  gapBufferInit(stat->rgst.yankedLine);
  insNewLine(stat->rgst.yankedLine, stat, 0);
  stat->rgst.yankedStr = (charArray*)malloc(sizeof(charArray));
  charArrayInit(stat->rgst.yankedStr);
  stat->rgst.numOfYankedLines = 0;
  stat->rgst.numOfYankedStr = 0;
}

int returnLine(gapBuffer *gb, editorStat *stat){
  if(stat->numOfLines > stat->trueLineCapa){
    stat->trueLineCapa = stat->numOfLines * 2;
    int *tmp = (int*)realloc(tmp, sizeof(stat->trueLineCapa));
    if(tmp == NULL){
      printf("main trueLine: cannot allocate memory...\n");
      return -1;
    }
    stat->trueLine = tmp;
  }

  for(int i=0; i<stat->numOfLines; i++){
    if(gapBufferAt(gb, i)->numOfChar > (COLS - stat->lineDigitSpace)){
      insNewLine(gb, stat, i + 1);
      charArray* leftLine = gapBufferAt(gb, i), *rightLine = gapBufferAt(gb, i + 1);
      int leftLineLength = COLS - stat->lineDigitSpace, rightLineLength = leftLine->numOfChar - leftLineLength;
      for(int j = 0; j < rightLineLength; ++j) charArrayPush(rightLine, leftLine->elements[leftLineLength + j]);
      for(int j = 0; j < rightLineLength; ++j) charArrayPop(leftLine);
      stat->trueLine[i + 1] = false;
    }
  }
  return 0;
}

int saveFile(WINDOW **win, gapBuffer* gb, editorStat *stat){

  if(strcmp(stat->filename, "No name") == 0){
    int   i = 0;
    char  ch, 
          filename[256];
    wattron(win[2], COLOR_PAIR(4));
    werase(win[2]);
    wprintw(win[2], "Please file name: ");
    wrefresh(win[2]);
    wattron(win[2], COLOR_PAIR(3));
    echo();
    wgetch(win[2]);   // skip enter 
    while(1){
      if((ch = wgetch(win[2])) == 10 || i > 255) break;
      filename[i] = ch;
      i++;
    }
    noecho();
    strcpy(stat->filename, filename);
    werase(win[2]);
  }
  
  FILE *fp;
  if ((fp = fopen(stat->filename, "w")) == NULL) {
    printf("%s Cannot file open... \n", stat->filename);
      return -1;
    }
  
  for(int i=0; i < gb->size; i++){
    fputs(gapBufferAt(gb, i)->elements, fp);
    if(i != gb->size - 1) fputc('\n', fp);
  }

  mvwprintw(win[2], 0, 0, "saved..., %d times changed", stat->numOfChange);
  wrefresh(win[2]);

  fclose(fp);
  stat->numOfChange = 0;

  return 0;
}

int countLineDigit(editorStat *stat, int numOfLines){
  int lineDigit = 0;
  while(numOfLines > 0){
    numOfLines /= 10;
    lineDigit++;
  }
  if(lineDigit > stat->lineDigit){
    stat->lineDigit = lineDigit;
    stat->lineDigitSpace = lineDigit + 1;
  }
  return lineDigit;
}

int printCurrentLine(WINDOW **win, gapBuffer *gb, editorStat *stat){
  if(stat->trueLine[stat->currentLine] == false) return 0;
  int lineDigitSpace = stat->lineDigit - countLineDigit(stat, stat->currentLine + 1);
  for(int j=0; j<lineDigitSpace; j++) mvwprintw(win[0], stat->y, j, " ");
  wattron(win[0], COLOR_PAIR(7));
  mvwprintw(win[0], stat->y, lineDigitSpace, "%d", stat->currentLine + 1);
  wmove(win[0], stat->y, stat->x);
  wrefresh(win[0]);
  wattron(win[0], COLOR_PAIR(6));
  return 0;
}

int printLineNum(WINDOW **win, editorStat *stat, int currentLine, int y){
  if(stat->trueLine[currentLine] == false){
    int lineDigitSpace = stat->lineDigit - countLineDigit(stat, currentLine + 1);
    for(int j=0; j<lineDigitSpace; j++) mvwprintw(win[0], y, j, " ");
  }else{
    int lineDigitSpace = stat->lineDigit - countLineDigit(stat, currentLine + 1);
    for(int j=0; j<lineDigitSpace; j++) mvwprintw(win[0], y, j, " ");
    wattron(win[0], COLOR_PAIR(3));
    mvwprintw(win[0], y, lineDigitSpace, "%d", currentLine + 1);
  }
  return 0;
}

// print single line
void printLine(WINDOW **win, gapBuffer* gb, editorStat *stat, int currentLine, int y){
  printLineNum(win, stat, currentLine, y);
  wattron(win[0], COLOR_PAIR(6));
  mvwprintw(win[0], y, stat->lineDigit + 1, "%s", gapBufferAt(gb, currentLine)->elements);
  wrefresh(win[0]);
}

void printLineAll(WINDOW **win, gapBuffer *gb, editorStat *stat){
  werase(win[0]);
  int currentLine = stat->currentLine - stat->y;
  for(int i=0; i<LINES-2; i++){
    if(currentLine == stat->numOfLines) break;
    printLineNum(win, stat, currentLine, i);
    printLine(win, gb, stat, currentLine, i);
    currentLine++;
  }
  printCurrentLine(win, gb, stat);
}

void printStatBarInit(WINDOW **win, gapBuffer *gb, editorStat *stat){
  werase(win[1]);
  wbkgd(win[1], COLOR_PAIR(1));
  printStatBar(win, gb, stat);
}

void printStatBar(WINDOW **win, gapBuffer *gb, editorStat *stat){
  werase(win[1]);
  wattron(win[1], COLOR_PAIR(2));
  if(stat->mode == NORMAL_MODE)
    wprintw(win[1], "%s ", " NORMAL");
  else if(stat->mode == INSERT_MODE)
    wprintw(win[1], "%s ", " INSERT");
  wattron(win[1], COLOR_PAIR(1));
  wprintw(win[1], " %s ", stat->filename);
  mvwprintw(win[1], 0, COLS-13, "%d/%d ", stat->currentLine + 1, stat->numOfLines);
  mvwprintw(win[1], 0, COLS-6, " %d/%d", stat->x - stat->lineDigitSpace + 1, gapBufferAt(gb, stat->currentLine)->numOfChar);
  wrefresh(win[1]);
}

int commandBar(WINDOW **win, gapBuffer *gb, editorStat *stat){
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
      saveFile(win, gb, stat);
      break;
    case 'q':
      exitCurses();
      break;
    case 't':
      def_prog_mode();           /* save current tty modes */
      endwin();                  /* restore original tty modes */
      system("sh");              /* run shell */
      reset_prog_mode();
      refresh();               /* restore save modes, repaint screen */
      break;
  }
  cbreak();
  return 0;
}

int insNewLine(gapBuffer *gb, editorStat *stat, int position){
  charArray* ca = (charArray*)malloc(sizeof(charArray));
  charArrayInit(ca);
  gapBufferInsert(gb, ca, position);
  stat->numOfLines++;
  return 0;
}

// Tab key is 2 space
int insertTab(gapBuffer *gb, editorStat *stat){
  for(int i=0; i<2; i++){
    charArrayInsert(gapBufferAt(gb, stat->currentLine), ' ', stat->x - stat->lineDigit);
    stat->x++;
    }
  stat->numOfChange++;
  stat->isViewUpdated = true;
  return 0;
}

int keyUp(gapBuffer* gb, editorStat* stat){
  if(stat->currentLine == 0) return 0;
  if(stat->y == 0){
    stat->currentLine--;
    stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
    stat->numOfChange++;
  }else{
    stat->y--;
    stat->currentLine--;
    if(stat->x > stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1)
      stat->x = stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1;
  }
  stat->isViewUpdated = true;
  return 0;
}

int keyDown(gapBuffer* gb, editorStat* stat){
  if(stat->currentLine + 1 == stat->numOfLines) return 0;
  if(stat->y == LINES - 3){
    stat->currentLine++;
    stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace;
    stat->numOfChange++;
  }else{
    stat->y++;
    stat->currentLine++;

    if(stat->mode == NORMAL_MODE)
      if (stat->x != stat->lineDigitSpace && stat->lineDigitSpace + gapBufferAt(gb, stat->currentLine)->numOfChar)
        stat->x = stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar;

    if(stat->x > stat->lineDigitSpace + gapBufferAt(gb, stat->currentLine)->numOfChar)
      stat->x = stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1;
  }
  stat->isViewUpdated = true;
  return 0;
}

int keyRight(gapBuffer* gb, editorStat* stat){
  if(stat->x >= gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace) return 0;
  if(stat->x >= gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1 && stat->mode == NORMAL_MODE) return 0;
  stat->x++;
  return 0;
}

int keyLeft(gapBuffer* gb, editorStat* stat){
  if(stat->x == stat->lineDigit + 1) return 0;
  stat->x--;
  return 0;
}

int keyBackSpace(gapBuffer* gb, editorStat* stat){
  if(stat->y == 0 && stat->x == stat->lineDigitSpace) return 0;
  stat->x--;
  if(stat->x < stat->lineDigitSpace  && gapBufferAt(gb, stat->currentLine)->numOfChar == 0){
    gapBufferDel(gb, stat->currentLine, stat->currentLine + 1);
    stat->numOfLines--;
    stat->x = stat->lineDigitSpace + gapBufferAt(gb, --stat->currentLine)->numOfChar;
    stat->y++;
    stat->currentLine--;
  }else if(stat->x < stat->lineDigitSpace && gapBufferAt(gb, stat->currentLine - 1)->numOfChar == 0){
    gapBufferDel(gb, stat->currentLine - 1, stat->currentLine);
    stat->numOfLines--;
    stat->currentLine--;
  }else if(stat->x < stat->lineDigitSpace && gapBufferAt(gb, stat->currentLine)->numOfChar > 0){
    int tmpNumOfChar = gapBufferAt(gb, stat->currentLine - 1)->numOfChar;
      for(int i=0; i<gapBufferAt(gb, stat->currentLine)->numOfChar; i++) {
        charArrayPush(gapBufferAt(gb, stat->currentLine - 1), gapBufferAt(gb, stat->currentLine)->elements[i]);
    }
    gapBufferDel(gb, stat->currentLine, stat->currentLine + 1);
    stat->numOfLines--;
    stat->x = stat->lineDigitSpace + tmpNumOfChar;
    stat->y--;
    stat->currentLine--;
  }else{
   charArrayDel(gapBufferAt(gb, stat->currentLine), (stat->x - stat->lineDigitSpace));
  }
  stat->isViewUpdated = true;
  stat->numOfChange++;
  return 0;
}

int insIndent(gapBuffer *gb, editorStat *stat){
  if(gapBufferAt(gb, stat->currentLine)->elements[0] == ' '){
    int i = 0;
    for(i=0; i<gapBufferAt(gb, stat->currentLine)->numOfChar; i++){
      if(gapBufferAt(gb, stat->currentLine)->elements[i] == ' ')
        charArrayPush(gapBufferAt(gb, stat->currentLine + 1), ' ');
      else break;
    }
   stat->x = stat->lineDigitSpace + i;
  }
  return 0;
}

int keyEnter(gapBuffer* gb, editorStat* stat){
  if(stat->x == stat->lineDigitSpace){    // beginning of line
    insNewLine(gb, stat, stat->currentLine);
    stat->currentLine++;
    if(stat->y != LINES - 3) stat->y++;
  }else{
    insNewLine(gb, stat, stat->currentLine + 1);

    charArray* leftLine = gapBufferAt(gb, stat->currentLine), *rightLine = gapBufferAt(gb, stat->currentLine + 1);
    const int leftLineLength = stat->x - stat->lineDigitSpace, rightLineLength = leftLine->numOfChar - leftLineLength;
    insIndent(gb, stat);

    for(int i = 0; i < rightLineLength; ++i) charArrayPush(rightLine, leftLine->elements[leftLineLength + i]);
    for(int i = 0; i < rightLineLength; ++i) charArrayPop(leftLine);
    insIndent(gb, stat);

    stat->currentLine++;
    if(stat->y != LINES - 3) stat->y++;
  }
  stat->isViewUpdated = true;
  stat->numOfChange++;
  return 0;
}

int keyO(gapBuffer *gb, editorStat *stat){
  insNewLine(gb, stat, stat->currentLine + 1);
  insIndent(gb, stat);    // does not works...
  stat->currentLine++;
  stat->x = stat->lineDigitSpace;
  stat->y++;
  stat->isViewUpdated = true;
  stat->numOfChange++;
  return 0;
}

int keyA(gapBuffer *gb, editorStat *stat){
  if(stat->x >= gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace)
    return 0;
    stat->x++;
  return 0;
}

int keyX(gapBuffer *gb, editorStat *stat){
  if(stat->x >= gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1){
    stat->currentLine++;
    stat->y++;
    stat->x = stat->lineDigitSpace;
    keyBackSpace(gb, stat);
  }else{
    charArrayDel(gapBufferAt(gb, stat->currentLine), (stat->x - stat->lineDigitSpace));
  }
  stat->isViewUpdated = true;
  stat->numOfChange++;
  return 0;
}

int keyD(WINDOW **win, gapBuffer *gb, editorStat *stat){
  gapBufferDel(gb, stat->currentLine, stat->currentLine + 1);

  if(stat->numOfLines == 1){
    charArray* emptyLine = (charArray*)malloc(sizeof(charArray));
    charArrayInit(emptyLine);
    gapBufferInsert(gb, emptyLine, 0);
  }else{
    stat->numOfLines--;

    if(stat->currentLine == stat->numOfLines){
      --stat->currentLine;
      if(stat->y > 0) --stat->y;
    }
  }

  stat->numOfChange++;
  stat->isViewUpdated = true;
  werase(win[2]);
  wprintw(win[2], "%d line deleted");
  return 0;
}

// does not works...
int replaceChar(gapBuffer *gb, editorStat *stat, int key){
  for(int i=0; i<stat->cmdLoop; i++){
    gapBufferAt(gb, stat->currentLine)->elements[(stat->x - stat->lineDigitSpace) + i] = key;
  }
  stat->numOfChange++;
  stat->isViewUpdated = true;
  return 0;
}

int moveFirstLine(WINDOW **win, gapBuffer *gb, editorStat *stat){
  int key;
  while(1){
    key = wgetch(win[0]);
    if(key == 'g'){
      stat->y = 0;
      stat->x = stat->lineDigitSpace;
      stat->currentLine = 0;
      stat->isViewUpdated = true;
      break;
    }else if(key == KEY_ESC)  break;;
  }
  return 0;
}

int moveLastLine(gapBuffer *gb, editorStat *stat){
  stat->y = LINES - 3;
  stat->currentLine = stat->numOfLines - 1;
  stat->x = stat->lineDigitSpace;
  stat->isViewUpdated = true;
  return 0;
}

int charInsert(gapBuffer *gb, editorStat *stat, int key){
  charArrayInsert(gapBufferAt(gb, stat->currentLine), key, stat->x - stat->lineDigitSpace);
  stat->x++;
  stat->numOfChange++;
  stat->isViewUpdated = true;
  return 0;
}

int lineYank(WINDOW **win, gapBuffer *gb, editorStat *stat){
  if(wgetch(win[0]) == 'y'){
    if(stat->cmdLoop > stat->numOfLines - stat->currentLine)
      stat->cmdLoop = stat->numOfLines - stat->currentLine;
    stat->rgst.numOfYankedLines = 0;
    int currentLine = stat->currentLine;
    for(int i=0; i<stat->cmdLoop; i++){
      gapBufferInsert(stat->rgst.yankedLine, gapBufferAt(gb, currentLine++), stat->rgst.numOfYankedLines++);
    }
    werase(win[2]);
    wprintw(win[2], "%d line yanked", stat->cmdLoop);
    wrefresh(win[2]);
  }
  return 0;
}

int linePaste(gapBuffer *gb, editorStat *stat){
  int currentLine = stat->currentLine;
  for(int i=0; i<stat->rgst.numOfYankedLines; i++){
    gapBufferInsert(gb, gapBufferAt(stat->rgst.yankedLine, i) , ++currentLine);
    stat->numOfLines++;
  }
  stat->numOfChange++;
  stat->isViewUpdated = true;
  return 0;
}

void cmdNormal(WINDOW **win, gapBuffer *gb, editorStat *stat, int key){
  if(stat->cmdLoop == 0) stat->cmdLoop = 1;
  switch(key){
    case KEY_LEFT:
    case 127:   // 127 is backspace key
    case 'h':
      for(int i=0; i<stat->cmdLoop; i++) keyLeft(gb, stat);
      break;
    case KEY_DOWN:
    case 10:    // 10 is Enter key
    case 'j':
      for(int i=0; i<stat->cmdLoop; i++) keyDown(gb, stat);
     break;
    case KEY_UP:
    case 'k':
      for(int i=0; i<stat->cmdLoop; i++) keyUp(gb, stat);
      break;
    case KEY_RIGHT:
    case 'l':
      for(int i=0; i<stat->cmdLoop; i++) keyRight(gb, stat);
      break;
    case '0':
    case KEY_HOME:
      stat->x = stat->lineDigitSpace;
      break;
    case '$':
    case KEY_END:
      stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
      break;
    case 'g':
      moveFirstLine(win, gb, stat);
      break;
    case 'G':
      moveLastLine(gb, stat);
      break;

    case KEY_DC:
    case 'x':
      if(stat->cmdLoop > gapBufferAt(gb,stat->currentLine)->numOfChar - (stat->x - stat->lineDigitSpace))
        stat->cmdLoop  = gapBufferAt(gb,stat->currentLine)->numOfChar - (stat->x - stat->lineDigitSpace);
        for(int i=0; i<stat->cmdLoop; i++) keyX(gb, stat);
      break;
    case 'd':
      if(wgetch(win[0]) == 'd'){
        if(stat->cmdLoop > stat->numOfLines - stat->currentLine)
          stat->cmdLoop = stat->numOfLines - stat->currentLine;
        for(int i=0; i<stat->cmdLoop; i++) keyD(win, gb, stat);
      }
      break;
    case 'y':
      lineYank(win, gb, stat);
      break;
    case 'p':
      linePaste(gb, stat);
      break;

    case 'r':
      key = wgetch(win[0]);
      replaceChar(gb, stat, key);
      break;
    case 'a':
      keyA(gb, stat);
      insertMode(win, gb, stat);
      break;
    case 'o':
      for(int i=0; i<stat->cmdLoop; i++) keyO(gb, stat);
      insertMode(win, gb, stat);
      break;
    case 'i':
      insertMode(win, gb, stat);
      break;
  }
}

void normalMode(WINDOW **win, gapBuffer *gb, editorStat *stat){
  int key;
  stat->cmdLoop = 0;
  stat->mode = NORMAL_MODE;
  noecho();

  while(1){
    printStatBar(win, gb, stat); 
    if(stat->isViewUpdated == true){
      printLineAll(win, gb, stat);
      stat->isViewUpdated = false;
      stat->cmdLoop = 0;
    }
    debugMode(win, gb, stat);
    wmove(win[0], stat->y, stat->x);
    key = wgetch(win[0]);

    if(key >= '0' && key <= '9'){
      if(stat->cmdLoop > 0){
        stat->cmdLoop *= 10;
        stat->cmdLoop += key - 48;
      }else{
        if(key == '0') cmdNormal(win, gb, stat, key);
        else stat->cmdLoop = key - 48;
      }
    }
    else if(key == KEY_ESC) stat->cmdLoop = 0;
    else if(key == KEY_RESIZE) winResizeEvent(win, gb, stat);
    else if(key == ':') commandBar(win, gb, stat);
    else{
      cmdNormal(win, gb, stat, key);
      stat->cmdLoop = 0;
    }
  }
}

void insertMode(WINDOW **win, gapBuffer* gb, editorStat* stat){
  int key;
  stat->mode = INSERT_MODE;
  noecho();

  while(1){
    printStatBar(win, gb, stat);
    if(stat->isViewUpdated == true){
      printLineAll(win, gb, stat);
      stat->isViewUpdated = false;
    }
    debugMode(win, gb, stat);
    wmove(win[0], stat->y, stat->x);
    key = wgetch(win[0]);

    switch(key){
      case KEY_UP:
        keyUp(gb, stat);
        break;
      case KEY_DOWN:
        keyDown(gb, stat);
        break;
      case KEY_RIGHT:
        keyRight(gb, stat);
        break;
      case KEY_LEFT:
        keyLeft(gb, stat);
        break;
      case KEY_HOME:
        stat->x = stat->lineDigitSpace;
        break;
      case KEY_END:
        stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
        break;
        
      case 127:   // 127 is backspace key
        keyBackSpace(gb, stat);
        break;
      case KEY_DC:
        keyX(gb, stat);
        break;

      case 10:    // 10 is Enter key
        keyEnter(gb, stat);
        break;

      case 9:   // 9 is Tab key;
        insertTab(gb, stat);
        break;

      case KEY_RESIZE:
        winResizeEvent(win, gb, stat);
        break;
      case KEY_ESC:
        normalMode(win, gb, stat);
        break;
      
      default:
        charInsert(gb, stat, key);
    }
  }
}

int openFile(char* filename){
  FILE *fp = fopen(filename, "r");
  if(fp == NULL){
		printf("%s Cannot file open... \n", filename);
		exit(0);
  }

  editorStat* stat = (editorStat*)malloc(sizeof(editorStat));
  editorStatInit(stat);

  gapBuffer* gb = (gapBuffer*)malloc(sizeof(gapBuffer));
  gapBufferInit(gb);
  insNewLine(gb, stat, 0);

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

  WINDOW **win = (WINDOW**)malloc(sizeof(WINDOW*)*3);
  if(signal(SIGINT, signal_handler) == SIG_ERR ||
     signal(SIGQUIT, signal_handler) == SIG_ERR){
    fprintf(stderr, "signal failure\n");
    exit(EXIT_FAILURE);
  }
  if(initscr() == NULL){
    fprintf(stderr, "initscr failure\n");
    exit(EXIT_FAILURE);
  }

  startCurses(stat);
  winInit(win);

  if(stat->lineDigit < countLineDigit(stat, stat->currentLine + 1))
    stat->lineDigit = countLineDigit(stat, stat->currentLine + 1);

  stat->numOfLines = stat->currentLine + 1;
  stat->x = stat->lineDigitSpace;
  stat->currentLine = 0;

  returnLine(gb, stat);

  printLineAll(win, gb, stat);
  printStatBarInit(win, gb, stat);

  normalMode(win, gb, stat);

  gapBufferFree(gb);

  return 0;
}

int newFile(){

  editorStat* stat = (editorStat*)malloc(sizeof(editorStat));
  editorStatInit(stat);

  gapBuffer* gb = (gapBuffer*)malloc(sizeof(gapBuffer));
  gapBufferInit(gb);
  insNewLine(gb, stat, 0);

  WINDOW **win = (WINDOW**)malloc(sizeof(WINDOW*)*3);
  if(signal(SIGINT, signal_handler) == SIG_ERR ||
     signal(SIGQUIT, signal_handler) == SIG_ERR){
    fprintf(stderr, "signal failure\n");
    exit(EXIT_FAILURE);
  }
  if(initscr() == NULL){
    fprintf(stderr, "initscr failure\n");
    exit(EXIT_FAILURE);
  }
  startCurses(stat);
  winInit(win);

  stat->x = stat->lineDigitSpace;
  stat->numOfLines = 1;

  printLineAll(win, gb, stat);
  printStatBarInit(win, gb, stat);

  normalMode(win, gb, stat);

  gapBufferFree(gb);

  return 0;
}

int main(int argc, char* argv[]){

  if(argc < 2){
    newFile();
  }

  openFile(argv[1]);

  return 0;
}
