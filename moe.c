#include <assert.h>
#include"moe.h"


void printStatBarInit(WINDOW **win, gapBuffer *gb, editorStat *stat);
void printStatBar(WINDOW **win, gapBuffer *gb, editorStat *stat);

int debugMode(WINDOW **win, gapBuffer *gb, editorStat *stat){
  stat->debugMode = ON;
  if(stat->debugMode == OFF ) return 0;
  werase(win[2]);
  mvwprintw(win[2], 0, 0, "debug mode: ");
  wprintw(win[2], "currentLine: %d ", stat->currentLine);
  wprintw(win[2], "numOfLines: %d ", stat->numOfLines);
  wprintw(win[2], "numOfChar: %d ", gapBufferAt(gb, stat->currentLine)->numOfChar);
  wprintw(win[2], "change: %d", stat->numOfChange);
  wprintw(win[2], "elements: %s", gapBufferAt(gb, stat->currentLine)->elements);
  wrefresh(win[2]);
  wmove(win[0], stat->cursor.y, stat->lineDigitSpace+stat->cursor.x);
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

void scrollUp(editorView* view, gapBuffer* buffer){
  view->isUpdated  = true;

  int height = view->height;
  charArray* newLine = view->lines[height-1];
  while(newLine->numOfChar > 0) charArrayPop(newLine);
  
  for(int y = height-1; y >= 1; --y){
    view->lines[y] = view->lines[y-1];
    view->originalLine[y] = view->originalLine[y-1];
    view->start[y] = view->start[y-1];
    view->length[y] = view->length[y-1];
  }
  if(view->start[1] > 0){
    view->originalLine[0] = view->originalLine[1];
    view->start[0] = view->start[1]-view->width;
    view->length[0] = view->width;
  }else{
    view->originalLine[0] = view->originalLine[1]-1;
    view->start[0] = view->width*((gapBufferAt(buffer, view->originalLine[0])->numOfChar-1)/view->width);
    view->length[0] = gapBufferAt(buffer, view->originalLine[0])->numOfChar == 0 ? 0 : (gapBufferAt(buffer, view->originalLine[0])->numOfChar-1)%view->width+1;
  }

  for(int x = 0; x < view->length[0]; ++x) charArrayPush(newLine, gapBufferAt(buffer, view->originalLine[0])->elements[x+view->start[0]]);
  view->lines[0] = newLine;
}

void scrollDown(editorView* view, gapBuffer* buffer){
  view->isUpdated = true;

  charArray* newLine = view->lines[0];
  while(newLine->numOfChar > 0) charArrayPop(newLine);

  int height = view->height;
  for(int y = 0; y < height-1; ++y){
    view->lines[y] = view->lines[y+1];
    view->originalLine[y] = view->originalLine[y+1];
    view->start[y] = view->start[y+1];
    view->length[y] = view->length[y+1];
  }
  
  if(view->start[height-2]+view->length[height-2] == gapBufferAt(buffer, view->originalLine[height-2])->numOfChar){
    view->originalLine[height-1] = view->originalLine[height-2]+1;
    view->start[height-1] = 0;
    view->length[height-1] = view->width > gapBufferAt(buffer, view->originalLine[height-1])->numOfChar ? gapBufferAt(buffer, view->originalLine[height-1])->numOfChar : view->width;
  }else{
    view->originalLine[height-1] = view->originalLine[height-2];
    view->start[height-1] = view->start[height-2]+view->length[height-2];
    view->length[height-1] = view->width > gapBufferAt(buffer, view->originalLine[height-1])->numOfChar - view->start[height-1] ? gapBufferAt(buffer, view->originalLine[height-1])->numOfChar - view->start[height-1] : view->width;
  }
  for(int x = 0; x < view->length[height-1]; ++x) charArrayPush(newLine, gapBufferAt(buffer, view->originalLine[height-1])->elements[x+view->start[height-1]]);
  view->lines[height-1] = newLine;
}

void updateCursorPosition(editorStat* stat){
  editorView* view = &stat->view;
  for(int y = 0; y < view->height; ++y) if(stat->currentLine == view->originalLine[y] && (view->length[y] == 0 || (view->start[y] <= stat->positionInCurrentLine && stat->positionInCurrentLine < view->start[y]+view->length[y]))){
    stat->cursor.y = y;
    stat->cursor.x = stat->positionInCurrentLine-view->start[y];
    break;
  }
}

void seekCursor(editorStat* stat, gapBuffer* buffer){
  stat->view.isUpdated = stat->cursor.isUpdated = true;
  editorView* view = &stat->view;
  while(stat->currentLine < view->originalLine[0] || (stat->currentLine == view->originalLine[0] && view->length[0] > 0 && stat->positionInCurrentLine < view->start[0])) scrollUp(view, buffer);
 
  while((view->originalLine[view->height-1] != -1 && stat->currentLine > view->originalLine[view->height-1]) || (stat->currentLine == view->originalLine[view->height-1] && view->length[view->height-1] > 0 && stat->positionInCurrentLine >= view->start[view->height-1]+view->length[view->height-1])) scrollDown(view, buffer);
}

void initEditorView(editorView* view, gapBuffer* buffer, int height, int width){
  view->height = height;
  view->width = width;
  view->lines = (charArray**)malloc(sizeof(charArray*)*height);
  view->originalLine = (int*)malloc(sizeof(int)*height);
  view->start = (int*)malloc(sizeof(int)*height);
  view->length = (int*)malloc(sizeof(int)*height);
  view->isUpdated = true;

  for(int y = 0; y < height; ++y){
    view->originalLine[y] = -1;
    view->lines[y] = (charArray*)malloc(sizeof(charArray));
    charArrayInit(view->lines[y]);
  }

  int lineNumber = 0, start = 0;
  for(int y = 0; y < height; ++y){
    if(lineNumber >= buffer->size) break;
    if(gapBufferAt(buffer, lineNumber)->numOfChar == 0){
      view->originalLine[y] = lineNumber;
      view->start[y] = 0;
      view->length[y] = 0;
      ++lineNumber;
      continue;
    }
    view->originalLine[y] = lineNumber;
    view->start[y] = start;
    view->length[y] = width > gapBufferAt(buffer, lineNumber)->numOfChar - start ? gapBufferAt(buffer, lineNumber)->numOfChar - start : width;
    for(int x = 0; x < view->length[y]; ++x) charArrayPush(view->lines[y], gapBufferAt(buffer, lineNumber)->elements[x+view->start[y]]);

    start += width;
    if(start >= gapBufferAt(buffer, lineNumber)->numOfChar){
      ++lineNumber;
      start = 0;
    }
  }
}

void resizeEditorView(editorView* view, gapBuffer* buffer, int height, int width){
  int lineNumber = view->originalLine[0], start = 0;
  for(int y = 0; y < view->height; ++y) charArrayFree(view->lines[y]);
  view->lines = (charArray**)realloc(view->lines, sizeof(charArray*)*height);
  view->height = height;
  view->width = width;
  view->originalLine = (int*)realloc(view->originalLine, sizeof(int)*height);
  view->start = (int*)realloc(view->start, sizeof(int)*height);
  view->length = (int*)realloc(view->length, sizeof(int)*height);
  view->isUpdated = true;

  for(int y = 0; y < height; ++y){
    view->originalLine[y]= -1;
    view->lines[y] = (charArray*)malloc(sizeof(charArray));
    charArrayInit(view->lines[y]);
  }

  for(int y = 0; y < height; ++y){
    if(lineNumber >= buffer->size) break;
    if(gapBufferAt(buffer, lineNumber)->numOfChar == 0){
      view->originalLine[y] = lineNumber;
      view->start[y] = 0;
      view->length[y] = 0;
      ++lineNumber;
      continue;
    }
    view->originalLine[y] = lineNumber;
    view->start[y] = start;
    view->length[y] = width > gapBufferAt(buffer, lineNumber)->numOfChar - start ? gapBufferAt(buffer, lineNumber)->numOfChar - start : width;
    for(int x = 0; x < view->length[y]; ++x) charArrayPush(view->lines[y], gapBufferAt(buffer, lineNumber)->elements[x+view->start[y]]);

    start += width;
    if(start >= gapBufferAt(buffer, lineNumber)->numOfChar){
      ++lineNumber;
      start = 0;
    }
  }
}

void winResizeEvent(WINDOW **win, gapBuffer *gb, editorStat *stat){
  endwin(); 
  initscr();
  winResizeMove(win[0], LINES-2, COLS, 0, 0);
  winResizeMove(win[1], 1, COLS, LINES-2, 0);
  winResizeMove(win[2], 1, COLS, LINES-1, 0);
  resizeEditorView(&stat->view, gb, LINES-2, COLS-stat->lineDigitSpace-1);
  seekCursor(stat, gb);
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
    wattron(win[2], COLOR_PAIR(4));
    werase(win[2]);
    wprintw(win[2], "Please file name: ");
    wrefresh(win[2]);
    wattron(win[2], COLOR_PAIR(3));
    echo();
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
    if(i != gb->size - 1) break;;
    if(stat->trueLine[i + 1] != false) fputc('\n', fp);
  }

  mvwprintw(win[2], 0, 0, "saved..., %d times changed", stat->numOfChange);
  wrefresh(win[2]);

  fclose(fp);
  stat->numOfChange = 0;

  return 0;
}

int countDigit(int num){
  int digit = 0;
  while(num > 0){
    ++digit;
    num /= 10;
  }
  return digit;
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
  int lineDigitSpace = stat->lineDigitSpace;
  for(int j=0; j<lineDigitSpace; j++) mvwprintw(win[0], y, j, " ");
  wattron(win[0], COLOR_PAIR(7));
  mvwprintw(win[0], y, lineDigitSpace, "%d", stat->currentLine - currentLine + 1 - stat->adjustLineNum);
  wmove(win[0], stat->cursor.y, stat->cursor.y);
  wrefresh(win[0]);
  wattron(win[0], COLOR_PAIR(6));
  return 0;
}

int printLineNum(WINDOW *textWindow, editorStat *stat, int line, int y){
  int lineDigitSpace = stat->lineDigitSpace;
  for(int j=0; j<lineDigitSpace; j++) mvwprintw(textWindow, y, j, " ");
  wattron(textWindow, COLOR_PAIR(line == stat->currentLine ? 7 : 3));
  mvwprintw(textWindow, y, 0, "%d", line + 1);
  return 0;
}

// print single line
void printLine(WINDOW *textWindow, editorStat* stat, charArray* line, int y){
  wattron(textWindow, COLOR_PAIR(6));
  mvwprintw(textWindow, y, stat->lineDigitSpace, "%s", line->elements);

}

void printAllLines(WINDOW *textWindow, gapBuffer *gb, editorStat *stat){
  wclear(textWindow);
  stat->lineDigit = countDigit(gb->size+1);
  stat->lineDigitSpace = stat->lineDigit+1;
  for(int y = 0; y < stat->view.height; ++y){
    if(stat->view.originalLine[y] == -1){
      for(int x = 0; x < COLS-1; ++x) mvwprintw(textWindow, y, x, " ");
      continue;
    }
    if(stat->view.start[y] == 0) printLineNum(textWindow, stat, stat->view.originalLine[y], y);
    printLine(textWindow, stat, stat->view.lines[y], y); 
  }
  wmove(textWindow, stat->cursor.y, stat->lineDigitSpace+stat->cursor.x);
  wrefresh(textWindow);
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
  mvwprintw(win[1], 0, COLS-6, " %d/%d", stat->positionInCurrentLine+1, gapBufferAt(gb, stat->currentLine)->numOfChar);
  wrefresh(win[1]);
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
  werase(win[2]);
  wprintw(win[2], "%s", ":");
  wrefresh(win[2]);
  echo();

  char cmd[COLS - 1];
  int saveFlag = false;
  wgetnstr(win[2], cmd, COLS - 1);
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
          wattron(win[2], COLOR_PAIR(4));
          werase(win[2]);
          wprintw(win[2], "%s","Erorr: No write since last change");
          wrefresh(win[2]);
          wattroff(win[2], COLOR_PAIR(4));
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
      werase(win[2]);
      wrefresh(win[2]);
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
 
  --stat->currentLine;
  stat->positionInCurrentLine = gapBufferAt(gb, stat->currentLine)->numOfChar-1 >= stat->positionInCurrentLine ? stat->positionInCurrentLine : gapBufferAt(gb, stat->currentLine)->numOfChar-1;
  if(stat->positionInCurrentLine < 0) stat->positionInCurrentLine = 0;
  seekCursor(stat, gb); 
  return 0;
}

int keyDown(gapBuffer* gb, editorStat* stat){
  if(stat->currentLine + 1 == gb->size) return 0;

  ++stat->currentLine;
  stat->positionInCurrentLine = gapBufferAt(gb, stat->currentLine)->numOfChar-1 >= stat->positionInCurrentLine ? stat->positionInCurrentLine : gapBufferAt(gb, stat->currentLine)->numOfChar-1;
  if(stat->positionInCurrentLine < 0) stat->positionInCurrentLine = 0;
  seekCursor(stat, gb);
  return 0;
}

int keyRight(gapBuffer* gb, editorStat* stat){
  if(stat->positionInCurrentLine+1 >= gapBufferAt(gb, stat->currentLine)->numOfChar) return 0;

  ++stat->positionInCurrentLine;
  seekCursor(stat, gb); 
  return 0;
}

int keyLeft(gapBuffer* gb, editorStat* stat){
  if(stat->positionInCurrentLine == 0) return 0;
  
  --stat->positionInCurrentLine;
  seekCursor(stat, gb); 
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
  werase(win[2]);
  wprintw(win[2], "%d line deleted");
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

  werase(win[2]);
  wprintw(win[2], "%d line yanked", stat->rgst.numOfYankedLines);
  wrefresh(win[2]);
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
      if(wgetch(win[0]) == 'd'){
        if(stat->cmdLoop > stat->numOfLines - stat->currentLine)
          stat->cmdLoop = stat->numOfLines - stat->currentLine;
        for(int i=0; i<stat->cmdLoop; i++) delLine(win, gb, stat);
      }
      break;
    case 'y':
      if(wgetch(win[0]) == 'y') lineYank(win, gb, stat);
      break;
    case 'p':
      linePaste(gb, stat);
      break;

    case 'r':
      key = wgetch(win[0]);
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
    if(stat->view.isUpdated){
      printAllLines(win[0], gb, stat);
      stat->view.isUpdated = false;
      stat->cmdLoop = 0;
    }
    if(stat->cursor.isUpdated){
      updateCursorPosition(stat);
      wmove(win[0], stat->cursor.y, stat->lineDigitSpace+stat->cursor.x);
      stat->cursor.isUpdated = false;
    }
    
    debugMode(win, gb, stat);
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
    if(stat->view.isUpdated){
      printAllLines(win[0], gb, stat);
      stat->view.isUpdated = false;
      stat->cmdLoop = 0;
    }
    if(stat->cursor.isUpdated){
      updateCursorPosition(stat);
      wmove(win[0], stat->cursor.y, stat->lineDigitSpace+stat->cursor.x);
      stat->cursor.isUpdated = false;
    }
    debugMode(win, gb, stat);
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

    stat->lineDigit = countDigit(stat->currentLine+1);
    stat->lineDigitSpace = stat->lineDigit+1;

    stat->numOfLines = stat->currentLine + 1;
    stat->x = stat->lineDigitSpace;
    stat->currentLine = 0;
    stat->positionInCurrentLine = 0;

    initEditorView(&stat->view, gb, LINES-2, COLS-stat->lineDigitSpace-1);
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
