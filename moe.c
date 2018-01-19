#include"moe.h"

int debugMode(WINDOW **win, gapBuffer *gb, editorStat *stat){
  stat->debugMode = ON;
  if(stat->debugMode == OFF ) return 0;
  werase(win[CMD_WIN]);
  mvwprintw(win[CMD_WIN], 0, 0, "debug mode: ");
  wprintw(win[CMD_WIN], "currentLine: %d ", stat->currentLine);
  wprintw(win[CMD_WIN], "numOfLines: %d ", stat->numOfLines);
  wprintw(win[CMD_WIN], "numOfChar: %d ", gapBufferAt(gb, stat->currentLine)->numOfChar);
  wprintw(win[CMD_WIN], "change: %d", stat->numOfChange);
  wprintw(win[CMD_WIN], "elements: %s", gapBufferAt(gb, stat->currentLine)->elements);
  wrefresh(win[CMD_WIN]);
  wmove(win[MAIN_WIN], stat->y, stat->x);
  return 0;
}

void winInit(WINDOW **win){
  win[MAIN_WIN] = newwin(LINES-2, COLS, 0, 0);    // main window
  win[STATE_WIN] = newwin(1, COLS, LINES-2, 0);    // status bar
  win[CMD_WIN] = newwin(1, COLS, LINES-1, 0);    // command bar
  keypad(win[MAIN_WIN], TRUE);   // enable function key
  keypad(win[STATE_WIN], TRUE);
  scrollok(win[CMD_WIN], TRUE);			// enable scroll
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
  if(initscr() == NULL){
    fprintf(stderr, "initscr failure\n");
    exit(EXIT_FAILURE);
  }

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
  winResizeMove(win[MAIN_WIN], LINES-2, COLS, 0, 0);
  winResizeMove(win[STATE_WIN], 1, COLS, LINES-2, 0);
  winResizeMove(win[CMD_WIN], 1, COLS, LINES-1, 0);
  returnLine(gb, stat);
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
  editorSettingInit(stat);
}

int trueLineInit(editorStat *stat){
  stat->adjustLineNum = 0;
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

int registersInit(editorStat *stat){
  stat->rgst.yankedLine = (gapBuffer*)malloc(sizeof(gapBuffer));
  if(stat->rgst.yankedLine == NULL){
    printf("main register: cannot allocated memory...\n");
    return -1;
  }
  gapBufferInit(stat->rgst.yankedLine);
  insNewLine(stat->rgst.yankedLine, stat, 0);
  stat->rgst.yankedStr = (charArray*)malloc(sizeof(charArray));
  if(stat->rgst.yankedStr == NULL){
    printf("main register: cannot allocated memory...\n");
    return -1;
  }
  charArrayInit(stat->rgst.yankedStr);
  stat->rgst.numOfYankedLines = 0;
  stat->rgst.numOfYankedStr = 0;

  return 0;
}

void editorSettingInit(editorStat *stat){
  stat->setting.autoCloseParen = ON;
  stat->setting.autoIndent = ON;
  stat->setting.tabStop = 2;
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

  int i = stat->currentLine - stat->y;
  int end = i + LINES - 2;
  for(i; i<end; i++){
    if(gapBufferAt(gb, i)->numOfChar > (COLS - stat->lineDigitSpace)){
      if(i == stat->numOfLines - 1) insNewLine(gb, stat, i + 1);
      else if(stat->trueLine[i + 1] == true) insNewLine(gb, stat, i + 1);
      charArray* leftLine = gapBufferAt(gb, i), *rightLine = gapBufferAt(gb, i + 1);
      int leftLineLength = COLS - stat->lineDigitSpace, rightLineLength = leftLine->numOfChar - leftLineLength;
      for(int j=0; j < rightLineLength; j++) charArrayInsert(rightLine, leftLine->elements[leftLineLength + j], j);
      for(int j = 0; j < rightLineLength; ++j) charArrayPop(leftLine);
      stat->trueLine[i + 1] = false;
    }else if(i != stat->numOfLines - 1 && gapBufferAt(gb, i)->numOfChar < (COLS - stat->lineDigitSpace)){
      if(stat->trueLine[i + 1] == false){
        charArray *leftLine = gapBufferAt(gb, i), *rightLine = gapBufferAt(gb, i + 1);
        int moveLength;
        if((COLS - stat->lineDigitSpace) - leftLine->numOfChar > rightLine->numOfChar) moveLength = rightLine->numOfChar;
        else moveLength = (COLS - stat->lineDigitSpace) - leftLine->numOfChar;
        for(int j = 0; j < moveLength; ++j) charArrayPush(leftLine, rightLine->elements[j]);
        for(int j = 0; j < moveLength; ++j) charArrayDel(rightLine, 0);
        if(rightLine->numOfChar == 0){
          gapBufferDel(gb, i + 1, i + 2);
          stat->numOfLines--;
          for(int k = i + 1; k < stat->numOfLines - 1; k++) stat->trueLine[k] = stat->trueLine[k + 1];
        }
      }
    }
  }
  return 0;
}

int saveFile(WINDOW **win, gapBuffer* gb, editorStat *stat){

  if(strcmp(stat->filename, "No name") == 0){
    int   i = 0;
    char  ch, 
          filename[256];
    wattron(win[CMD_WIN], COLOR_PAIR(4));
    werase(win[CMD_WIN]);
    wprintw(win[CMD_WIN], "Please file name: ");
    wrefresh(win[CMD_WIN]);
    wattron(win[CMD_WIN], COLOR_PAIR(3));
    echo();
    while(1){
      if((ch = wgetch(win[CMD_WIN])) == 10 || i > 255) break;
      filename[i] = ch;
      i++;
    }
    noecho();
    strcpy(stat->filename, filename);
    werase(win[CMD_WIN]);
  }
  
  FILE *fp;
  if ((fp = fopen(stat->filename, "w")) == NULL) {
    printf("%s Cannot file open... \n", stat->filename);
      return -1;
    }
  
  for(int i=0; i < gb->size; i++){
    fputs(gapBufferAt(gb, i)->elements, fp);
    if(i != gb->size - 1) break;;
    if(stat->trueLine[i + 1] != false) fputc('\n', fp);
  }

  mvwprintw(win[CMD_WIN], 0, 0, "saved..., %d times changed", stat->numOfChange);
  wrefresh(win[CMD_WIN]);

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
  int currentLine = stat->currentLine,
      y = stat->y;
  if(stat->trueLine[currentLine] == false){
    while(stat->trueLine[currentLine] != true){
      currentLine--;
      y--;
    }
  }else currentLine = 0;
  int lineDigitSpace = stat->lineDigit - countLineDigit(stat, stat->currentLine + 1);
  for(int j=0; j<lineDigitSpace; j++) mvwprintw(win[MAIN_WIN], y, j, " ");
  wattron(win[MAIN_WIN], COLOR_PAIR(7));
  mvwprintw(win[MAIN_WIN], y, lineDigitSpace, "%d", stat->currentLine - currentLine + 1 - stat->adjustLineNum);
  wmove(win[MAIN_WIN], stat->y, stat->x);
  wrefresh(win[MAIN_WIN]);
  wattron(win[MAIN_WIN], COLOR_PAIR(6));
  return 0;
}

int printLineNum(WINDOW **win, editorStat *stat, int currentLine, int y){
  if(stat->trueLine[currentLine] == false) return 0;
    int lineDigitSpace = stat->lineDigit - countLineDigit(stat, currentLine + 1);
    for(int j=0; j<lineDigitSpace; j++) mvwprintw(win[MAIN_WIN], y, j, " ");
    wattron(win[MAIN_WIN], COLOR_PAIR(3));
    mvwprintw(win[MAIN_WIN], y, lineDigitSpace, "%d", currentLine + 1 - stat->adjustLineNum);
  return 0;
}

// print single line
void printLine(WINDOW **win, gapBuffer* gb, editorStat *stat, int currentLine, int y){
  printLineNum(win, stat, currentLine, y);
  wattron(win[MAIN_WIN], COLOR_PAIR(6));
  mvwprintw(win[MAIN_WIN], y, stat->lineDigit + 1, "%s", gapBufferAt(gb, currentLine)->elements);
  wrefresh(win[MAIN_WIN]);
}

void printLineAll(WINDOW **win, gapBuffer *gb, editorStat *stat){
  werase(win[MAIN_WIN]);
  int startPrintLine = stat->currentLine - stat->y,
      currentLine = 0;
  stat->adjustLineNum = 0;
  for(int i=0; i<startPrintLine + LINES-2; i++){
    if(currentLine == stat->numOfLines) break;
    if(stat->trueLine[i] == false) stat->adjustLineNum++;
    if(i >= startPrintLine){
      printLineNum(win, stat, currentLine, i - startPrintLine);
      printLine(win, gb, stat, currentLine, i - startPrintLine);
      if(currentLine == stat->currentLine) printCurrentLine(win, gb, stat);
    }
    currentLine++;
  }
}

void printStatBarInit(WINDOW **win, gapBuffer *gb, editorStat *stat){
  werase(win[STATE_WIN]);
  wbkgd(win[STATE_WIN], COLOR_PAIR(1));
  printStatBar(win, gb, stat);
}

void printStatBar(WINDOW **win, gapBuffer *gb, editorStat *stat){
  werase(win[STATE_WIN]);
  wattron(win[STATE_WIN], COLOR_PAIR(2));
  if(stat->mode == NORMAL_MODE)
    wprintw(win[STATE_WIN], "%s ", " NORMAL");
  else if(stat->mode == INSERT_MODE)
    wprintw(win[STATE_WIN], "%s ", " INSERT");
  wattron(win[STATE_WIN], COLOR_PAIR(1));
  wprintw(win[STATE_WIN], " %s ", stat->filename);
  if(strcmp(stat->filename, "No name") == 0) wprintw(win[STATE_WIN], " [+]");
  mvwprintw(win[STATE_WIN], 0, COLS-13, "%d/%d ", stat->currentLine + 1, stat->numOfLines);
  mvwprintw(win[STATE_WIN], 0, COLS-6, " %d/%d", stat->x - stat->lineDigitSpace + 1, gapBufferAt(gb, stat->currentLine)->numOfChar);
  wrefresh(win[STATE_WIN]);
}

int shellMode(char *cmd){
  for(int j=0; j<strlen(cmd) - 2; j++) cmd[j] = cmd[j + 2];
  cmd[strlen(cmd) - 2] = '\0';
  def_prog_mode();    // Save the tty modes
	endwin();
	system(cmd);
  system("printf \"\nPress Enter\"");
  system("read _");
	reset_prog_mode();    // Return to the previous tty mode

  return 0;
}

// has problem...
int jampLine(editorStat *stat, int lineNum){
  const int startPrintLine = stat->currentLine - stat->y;
  if(lineNum >= startPrintLine || lineNum < (startPrintLine + COLS - 2)){
    stat->y = lineNum - startPrintLine;
    stat->currentLine = lineNum;
  }else{
    stat->y = 0;
    stat->x = stat->lineDigitSpace;
    stat->currentLine = lineNum;
  }
  stat->isViewUpdated = true;
  return 0;
}

int commandBar(WINDOW **win, gapBuffer *gb, editorStat *stat){
  werase(win[CMD_WIN]);
  wprintw(win[CMD_WIN], "%s", ":");
  wrefresh(win[CMD_WIN]);
  echo();

  char cmd[COLS - 1];
  int saveFlag = false;
  wgetnstr(win[CMD_WIN], cmd, COLS - 1);
  noecho();

  for(int i=0; i<strlen(cmd); i++){
    if(cmd[0] >= '0' && cmd[0] <= '9'){
      int lineNum = atoi(cmd) - 1;
      if(lineNum < 0) lineNum = 0;
      else if(lineNum > stat->numOfLines) lineNum = stat->numOfLines;
      jampLine(stat, lineNum);
      return 0;
    }else if(cmd[i] == 'w'){
      saveFile(win, gb, stat);
      saveFlag = true;
    }else if(cmd[i] == 'q'){
      if(cmd[i + 1] == '!' || stat->numOfChange == 0) exitCurses();
      else if(cmd[i + 1] != '!'){
        if(stat->numOfChange > 0 && saveFlag != true){
          wattron(win[CMD_WIN], COLOR_PAIR(4));
          werase(win[CMD_WIN]);
          wprintw(win[CMD_WIN], "%s","Erorr: No write since last change");
          wrefresh(win[CMD_WIN]);
          wattroff(win[CMD_WIN], COLOR_PAIR(4));
        }
      }
    }else if(cmd[0] == 'e'){  // File open
      char filename[256];
      strcpy(filename, cmd);
      for(int j=0; j<strlen(filename) - 2; j++) filename[j] = filename[j + 2];
      filename[strlen(filename) - 2] = '\0';
      cmdE(gb, stat, filename);
    }else if(cmd[0] == '!'){    // Shell command execution
      shellMode(cmd);
      werase(win[CMD_WIN]);
      wrefresh(win[CMD_WIN]);
    }
  }
  return 0;
}

int insNewLine(gapBuffer *gb, editorStat *stat, int position){
  charArray* ca = (charArray*)malloc(sizeof(charArray));
  if(ca == NULL){
    printf("main insert new line: cannot allocated memory...\n");
    return -1;
  }
  charArrayInit(ca);
  gapBufferInsert(gb, ca, position);
  stat->numOfLines++;
  return 0;
}

int insertTab(gapBuffer *gb, editorStat *stat){
  for(int i=0; i<stat->setting.tabStop; i++)
    charInsert(gb, stat, ' ');
  return 0;
}

int keyUp(gapBuffer* gb, editorStat* stat){
  if(stat->currentLine == 0) return 0;
  if(stat->y == 0){
    stat->currentLine--;
    stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace - 1;
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
  }else{
    stat->y++;
    stat->currentLine++;

    if(stat->mode == NORMAL_MODE){
      if (stat->x != stat->lineDigitSpace && stat->x > stat->lineDigitSpace + gapBufferAt(gb, stat->currentLine)->numOfChar)
        stat->x = stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar;
    }else if(stat->mode == INSERT_MODE){
      if(stat->x > stat->lineDigitSpace + gapBufferAt(gb, stat->currentLine)->numOfChar)
        stat->x = stat->lineDigit + gapBufferAt(gb, stat->currentLine)->numOfChar + 1;
    }
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
  if(stat->x < stat->lineDigitSpace && gapBufferAt(gb, stat->currentLine)->numOfChar == 0){
    gapBufferDel(gb, stat->currentLine, stat->currentLine + 1);
    stat->numOfLines--;
    stat->x = stat->lineDigitSpace + gapBufferAt(gb, --stat->currentLine)->numOfChar;
    stat->y--;

    if(stat->trueLine[stat->currentLine + 1] == false && stat->trueLine[stat->currentLine + 2] == true)
      stat->trueLine[stat->currentLine + 1] = true;
  }else if(stat->x < stat->lineDigitSpace && gapBufferAt(gb, stat->currentLine - 1)->numOfChar == 0){
    gapBufferDel(gb, stat->currentLine - 1, stat->currentLine);
    stat->numOfLines--;
    stat->currentLine--;

    if(stat->trueLine[stat->currentLine + 1] == false && stat->trueLine[stat->currentLine + 2] == true)
      stat->trueLine[stat->currentLine + 1] = true;
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

    if(stat->trueLine[stat->currentLine + 1] == false && stat->trueLine[stat->currentLine + 2] == true)
      stat->trueLine[stat->currentLine + 1] = true;
  }else{
   charArrayDel(gapBufferAt(gb, stat->currentLine), (stat->x - stat->lineDigitSpace));
  }
  stat->isViewUpdated = true;
  stat->numOfChange++;
  return 0;
}

int insIndent(gapBuffer *gb, editorStat *stat){
  if(stat->setting.autoIndent != ON) return 0;
  if(gapBufferAt(gb, stat->currentLine)->elements[0] == ' '){
    int i = 0;
    while(gapBufferAt(gb, stat->currentLine)->elements[i] == ' '){
      charArrayPush(gapBufferAt(gb, stat->currentLine + 1), ' ');
      i++;
    }
  }
  return 0;
}

int keyEnter(gapBuffer* gb, editorStat* stat){
  if(stat->x == stat->lineDigitSpace){    // beginning of line
    if(stat->trueLine[stat->currentLine] == false){
      insNewLine(gb, stat, stat->currentLine - 1);
      stat->trueLine[stat->currentLine] = true;
      stat->currentLine++;
      stat->trueLine[stat->currentLine] = false;
    }else{
      insNewLine(gb, stat, stat->currentLine);
      stat->currentLine++;
    }
    if(stat->y != LINES - 3) stat->y++;
    stat->x = stat->lineDigitSpace;
  }else{
    insNewLine(gb, stat, stat->currentLine + 1);

    charArray* leftLine = gapBufferAt(gb, stat->currentLine), *rightLine = gapBufferAt(gb, stat->currentLine + 1);
    const int leftLineLength = stat->x - stat->lineDigitSpace, rightLineLength = leftLine->numOfChar - leftLineLength;
    insIndent(gb, stat);

    for(int i = 0; i < rightLineLength; ++i) charArrayPush(rightLine, leftLine->elements[leftLineLength + i]);
    for(int i = 0; i < rightLineLength; ++i) charArrayPop(leftLine);

    if(stat->trueLine[stat->currentLine] == false) stat->trueLine[stat->currentLine + 1] = false;
    stat->currentLine++;
    if(stat->y != LINES - 3) stat->y++;
    stat->x = stat->lineDigitSpace;
    int i=0;
    while(gapBufferAt(gb, stat->currentLine)->elements[i++] == ' ') stat->x++;
  }
  stat->isViewUpdated = true;
  stat->numOfChange++;
  return 0;
}

int openBlankLine(gapBuffer *gb, editorStat *stat){
  if(stat->trueLine[stat->currentLine + 1] == false){
    insNewLine(gb, stat, stat->currentLine + 2);
    stat->y += 2;
    stat->currentLine += 2;
  }else{
    insNewLine(gb, stat, stat->currentLine + 1);
    insIndent(gb, stat);
    stat->y++;
    stat->currentLine++;
  }
  stat->x = stat->lineDigitSpace;
  int i=0;
  while(gapBufferAt(gb, stat->currentLine)->elements[i++] == ' ') stat->x++;
  stat->isViewUpdated = true;
  stat->numOfChange++;
  return 0;
}

int appendAfterTheCursor(gapBuffer *gb, editorStat *stat){
  if(stat->x >= gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace)
    return 0;
    stat->x++;
  return 0;
}

int appendEndOfLine(gapBuffer *gb, editorStat *stat){
  stat->x = gapBufferAt(gb, stat->currentLine)->numOfChar + stat->lineDigitSpace;
  return 0;
}

int insBeginOfLine(gapBuffer *gb, editorStat *stat){
  stat->x = stat->lineDigitSpace;
  return 0;
}

int delCurrentChar(gapBuffer *gb, editorStat *stat){
  charArrayDel(gapBufferAt(gb, stat->currentLine), (stat->x - stat->lineDigitSpace));
  stat->isViewUpdated = true;
  stat->numOfChange++;
  return 0;
}

int delLine(WINDOW **win, gapBuffer *gb, editorStat *stat){
  gapBufferDel(gb, stat->currentLine, stat->currentLine + 1);

  if(stat->numOfLines == 1){
    charArray* emptyLine = (charArray*)malloc(sizeof(charArray));
    if(emptyLine == NULL){
      printf("main: cannot allocated memory...\n");
      return -1;
    }
    charArrayInit(emptyLine);
    gapBufferInsert(gb, emptyLine, 0);
  }else{
    stat->numOfLines--;

    if(stat->currentLine == stat->numOfLines){
      --stat->currentLine;
      if(stat->y > 0) --stat->y;
    }
  }

  stat->x = stat->lineDigitSpace;
  stat->numOfChange++;
  stat->isViewUpdated = true;
  werase(win[CMD_WIN]);
  wprintw(win[CMD_WIN], "%d line deleted");
  return 0;
}

int replaceChar(gapBuffer *gb, editorStat *stat, int key){
  if((stat->x - stat->lineDigitSpace) + stat->cmdLoop > gapBufferAt(gb, stat->currentLine)->numOfChar) return 0;
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
    key = wgetch(win[MAIN_WIN]);
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

  if(stat->setting.autoCloseParen == ON){
    if(key == '(')
      charArrayInsert(gapBufferAt(gb, stat->currentLine), ')', stat->x - stat->lineDigitSpace);
    if(key == '{')
      charArrayInsert(gapBufferAt(gb, stat->currentLine), '}', stat->x - stat->lineDigitSpace);
    if(key == '"')
      charArrayInsert(gapBufferAt(gb, stat->currentLine), '"', stat->x - stat->lineDigitSpace);
    if(key == '\'')
      charArrayInsert(gapBufferAt(gb, stat->currentLine), '\'', stat->x - stat->lineDigitSpace);
  }

  stat->numOfChange++;
  stat->isViewUpdated = true;
  return 0;
}

int lineYank(WINDOW **win, gapBuffer *gb, editorStat *stat){
  stat->rgst.numOfYankedLines = stat->cmdLoop > stat->numOfLines - stat->currentLine ? stat->numOfLines - stat->currentLine : stat->cmdLoop;
  
  for(int line = stat->currentLine; line < stat->currentLine + stat->rgst.numOfYankedLines; line++){
    gapBufferInsert(stat->rgst.yankedLine, charArrayCopy(gapBufferAt(gb, line)), line - stat->currentLine);
  }

  werase(win[CMD_WIN]);
  wprintw(win[CMD_WIN], "%d line yanked", stat->rgst.numOfYankedLines);
  wrefresh(win[CMD_WIN]);
  return 0;
}

int linePaste(gapBuffer *gb, editorStat *stat){
  for(int i=0; i<stat->rgst.numOfYankedLines; i++){
    gapBufferInsert(gb, charArrayCopy(gapBufferAt(stat->rgst.yankedLine, i)) , ++stat->currentLine);
    stat->numOfLines++;
  }
  stat->numOfChange++;
  stat->isViewUpdated = true;
  return 0;
}

int cmdE(gapBuffer *gb, editorStat *stat, char *filename){
  editorStatInit(stat);
  strcpy(stat->filename, filename);
  gapBufferFree(gb);
  gapBufferInit(gb);
  insNewLine(gb, stat, 0);
  openFile(gb, stat);
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
        for(int i=0; i<stat->cmdLoop; i++) delCurrentChar(gb, stat);
      break;
    case 'd':
      if(wgetch(win[MAIN_WIN]) == 'd'){
        if(stat->cmdLoop > stat->numOfLines - stat->currentLine)
          stat->cmdLoop = stat->numOfLines - stat->currentLine;
        for(int i=0; i<stat->cmdLoop; i++) delLine(win, gb, stat);
      }
      break;
    case 'y':
      if(wgetch(win[MAIN_WIN]) == 'y') lineYank(win, gb, stat);
      break;
    case 'p':
      linePaste(gb, stat);
      break;

    case 'r':
      key = wgetch(win[MAIN_WIN]);
      replaceChar(gb, stat, key);
      break;
    case 'a':
      appendAfterTheCursor(gb, stat);
      insertMode(win, gb, stat);
      break;
    case 'A':
      appendEndOfLine(gb, stat);
      insertMode(win, gb, stat);
      break;
    case 'I':
      insBeginOfLine(gb, stat);
      insertMode(win, gb, stat);
      break;
    case 'o':
      for(int i=0; i<stat->cmdLoop; i++) openBlankLine(gb, stat);
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
    wmove(win[MAIN_WIN], stat->y, stat->x);
    debugMode(win, gb, stat);
    key = wgetch(win[MAIN_WIN]);

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
    wmove(win[MAIN_WIN], stat->y, stat->x);
    key = wgetch(win[MAIN_WIN]);

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
        delCurrentChar(gb, stat);
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

int openFile(gapBuffer *gb, editorStat *stat){

  FILE *fp = fopen(stat->filename, "r");
  if(fp == NULL){
    stat->x = stat->lineDigitSpace;
    stat->numOfLines = 1;
  }else{
    char  ch;
    while((ch = fgetc(fp)) != EOF){
      if(ch=='\n'){
        stat->currentLine += 1;
        charArray* ca = (charArray*)malloc(sizeof(charArray));
        if(ca == NULL){
          printf("main read file: cannot allocated memory...\n");
          return -1;
        }
        charArrayInit(ca);
        gapBufferInsert(gb, ca, stat->currentLine);
      }else charArrayPush(gapBufferAt(gb, stat->currentLine), ch);
    }
    fclose(fp);

    if(stat->lineDigit < countLineDigit(stat, stat->currentLine + 1))
      stat->lineDigit = countLineDigit(stat, stat->currentLine + 1);

    stat->numOfLines = stat->currentLine + 1;
    stat->x = stat->lineDigitSpace;
    stat->currentLine = 0;

    returnLine(gb, stat);
  }

  return 0;
}

int newFile(editorStat *stat){
  stat->x = stat->lineDigitSpace;
  stat->numOfLines = 1;
  return 0;
}

int main(int argc, char* argv[]){

  editorStat *stat = (editorStat*)malloc(sizeof(editorStat));
  if(stat == NULL){
    printf("main: cannot allocated memory...\n");
    return -1;
  }
  editorStatInit(stat);

  gapBuffer *gb = (gapBuffer*)malloc(sizeof(gapBuffer));
  if(gb == NULL){
    printf("main: cannot allocated memory...\n");
    return -1;
  }
  gapBufferInit(gb);
  insNewLine(gb, stat, 0);

  WINDOW **win = (WINDOW**)malloc(sizeof(WINDOW*)*3);
  if(signal(SIGINT, signal_handler) == SIG_ERR ||
     signal(SIGQUIT, signal_handler) == SIG_ERR){
      fprintf(stderr, "signal failure\n");
      exit(EXIT_FAILURE);
  }

  startCurses(stat);
  winInit(win);

  if(argc < 2) newFile(stat);
  else{
    strcpy(stat->filename, argv[1]);
    openFile(gb, stat);
  }

  printStatBarInit(win, gb, stat);
  stat->isViewUpdated = true;

  normalMode(win, gb, stat);

  gapBufferFree(gb);

  return 0;
}
