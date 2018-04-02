#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <malloc.h>
#include <signal.h>
#include <ncurses.h>
#include <ctype.h>
#include "moe.h"
#include "mathutility.h"

#define KEY_ESC 27
#define COLOR_DEFAULT -1
#define BRIGHT_WHITE 231
#define BRIGHT_GREEN 85
#define GRAY 245
#define ON 1
#define OFF 0
#define NORMAL_MODE 0
#define INSERT_MODE 1
#define MAIN_WIN 0
#define STATE_WIN 1
#define CMD_WIN 2

void printStatBarInit(WINDOW **win, gapBuffer *gb, editorStat *stat);
void printStatBar(WINDOW **win, gapBuffer *gb, editorStat *stat);
int registersInit(editorStat *stat);
void editorSettingInit(editorStat *stat);
int insNewLine(gapBuffer *gb, editorStat *stat, int position);
int cmdE(gapBuffer *gb, editorStat *stat, char *filename);
int insertChar(gapBuffer *gb, editorStat *stat, int key);
void insertMode(WINDOW **win, gapBuffer* gb, editorStat* stat);

int debugMode(WINDOW **win, gapBuffer *gb, editorStat *stat){
#ifdef MOEDEBUG
  int returnY = stat->cursor.y,returnX = stat->cursor.x;
  werase(win[CMD_WIN]);
  mvwprintw(win[CMD_WIN], 0, 0, "debug mode: ");
  wprintw(win[CMD_WIN], "currentLine: %d ", stat->currentLine);
  wprintw(win[CMD_WIN], "numOfLines: %d ", gb->size);
  wprintw(win[CMD_WIN], "numOfChar: %d ", gapBufferAt(gb, stat->currentLine)->numOfChar);
  wprintw(win[CMD_WIN], "change: %d ", stat->numOfChange);
  wprintw(win[CMD_WIN], "cursor: %d ", stat->positionInCurrentLine);
  wprintw(win[CMD_WIN], "elements: %s", gapBufferAt(gb, stat->currentLine)->elements);
//  wprintw(win[CMD_WIN], "numOfYankedLines: %d", stat->rgst.numOfYankedLines);
//  wprintw(win[CMD_WIN], "yanked elements: %s", gapBufferAt(stat->rgst.yankedLine, 0)->elements);
  wrefresh(win[CMD_WIN]);
  wmove(win[MAIN_WIN], returnY, returnX+stat->view.widthOfLineNum);
#endif
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

int openFile(gapBuffer *gb, editorStat *stat){
  FILE *fp = fopen(stat->filename, "r");
  if(fp != NULL){
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

  }
  
  stat->currentLine = stat->positionInCurrentLine = stat->expandedPosition = 0;
  stat->cursor.isUpdated = true;
  freeEditorView(&stat->view);
  initEditorView(&stat->view, gb, &stat->cursor, LINES-2, COLS-(countDigit(gb->size+1)+1)-1);
  return 0;
}

int newFile(gapBuffer *gb, editorStat *stat){
  stat->currentLine = stat->positionInCurrentLine = 0;
  stat->cursor.isUpdated = true;
  initEditorView(&stat->view, gb, &stat->cursor, LINES-2, COLS-(countDigit(gb->size+1)+1)-1);
  return 0;
}

void winResizeEvent(WINDOW **win, gapBuffer *gb, editorStat *stat){
  endwin(); 
  initscr();
  winResizeMove(win[MAIN_WIN], LINES-2, COLS, 0, 0);
  winResizeMove(win[STATE_WIN], 1, COLS, LINES-2, 0);
  winResizeMove(win[CMD_WIN], 1, COLS, LINES-1, 0);
  resizeEditorView(&stat->view, gb, LINES-2, COLS-stat->view.widthOfLineNum-1, stat->view.widthOfLineNum);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  printStatBarInit(win, gb, stat);
}

void editorStatInit(editorStat* stat){
  stat->currentLine = 0;
  stat->positionInCurrentLine = 0;
  stat->expandedPosition = 0;
  stat->mode = NORMAL_MODE;
  stat->cmdLoop = 0;
  strcpy(stat->filename, "No name");
  stat->numOfChange = 0;
  stat->debugMode = OFF;
  registersInit(stat);
  editorSettingInit(stat);
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

int saveFile(WINDOW **win, gapBuffer* gb, editorStat *stat){

  if(strcmp(stat->filename, "No name") == 0){
    int   i = 0;
    char  ch, 
          filename[256];
    wattron(win[CMD_WIN], COLOR_PAIR(4));
    werase(win[CMD_WIN]);
    wprintw(win[CMD_WIN], "Please input file name: ");
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
    printf("%s Cannot open the file... \n", stat->filename);
      return -1;
    }
  
  for(int i=0; i < gb->size; i++){
    fprintf(fp, "%s",gapBufferAt(gb, i)->elements);
    if(i+1 < gb->size) fprintf(fp, "\n");
  }

  mvwprintw(win[CMD_WIN], 0, 0, "saved..., %d times changed", stat->numOfChange);
  wrefresh(win[CMD_WIN]);

  fclose(fp);
  stat->numOfChange = 0;

  return 0;
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
  mvwprintw(win[STATE_WIN], 0, COLS-13, "%d/%d ", stat->currentLine + 1, gb->size);
  mvwprintw(win[STATE_WIN], 0, COLS-6, " %d/%d", stat->positionInCurrentLine, gapBufferAt(gb, stat->currentLine)->numOfChar);
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

int jumpLine(editorStat* stat, gapBuffer* buffer, int destination){
  editorView* view = &stat->view;
  int currentLine = stat->currentLine;
  stat->currentLine = destination;
  stat->positionInCurrentLine = stat->expandedPosition = 0;
  if(!(view->originalLine[0] <= destination && (view->originalLine[view->height-1] == -1 || destination <= view->originalLine[view->height-1]))){
    int startOfPrintedLines = destination-(currentLine - view->originalLine[0]) >= 0 ?  destination-(currentLine - view->originalLine[0]) : 0;
    reloadEditorView(view, buffer, startOfPrintedLines);
  }
  seekCursor(&stat->view, buffer, stat->currentLine, stat->positionInCurrentLine);
  return 0;
}

int pageUp(gapBuffer *buffer, editorStat *stat){
  int destination = stat->currentLine - stat->view.height;
  if(destination < 0) destination = 0;
  jumpLine(stat, buffer, destination);
  return 0;
}

int pageDown(gapBuffer *buffer, editorStat *stat){
  int destination = stat->currentLine + stat->view.height;
  if(destination > buffer->size - 1) destination = buffer->size - 1;
  jumpLine(stat, buffer, destination);
  return 0;
}

int commandBar(WINDOW **win, gapBuffer *gb, editorStat *stat){
  werase(win[CMD_WIN]);
  wprintw(win[CMD_WIN], "%s", ":");
  wrefresh(win[CMD_WIN]);
  echo();

  char cmd[COLS - 1];
  memset(cmd, 0, COLS-1);
  int saveFlag = false;
  wgetnstr(win[CMD_WIN], cmd, COLS - 1);
  noecho();

  for(int i=0; i<strlen(cmd); i++){
    if(cmd[0] >= '0' && cmd[0] <= '9'){
      int lineNum = atoi(cmd) - 1;
      if(lineNum < 0) lineNum = 0;
      else if(lineNum >= gb->size) lineNum = gb->size-1;
      jumpLine(stat, gb,  lineNum);
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
  return 0;
}

int insertTab(gapBuffer *gb, editorStat *stat){
  for(int i=0; i<stat->setting.tabStop; i++)
    insertChar(gb, stat, ' ');
  return 0;
}

int keyUp(gapBuffer* gb, editorStat* stat){
  if(stat->currentLine == 0) return 0;
 
  --stat->currentLine;
  int maxPosition = gapBufferAt(gb, stat->currentLine)->numOfChar-1+(stat->mode == INSERT_MODE);
  stat->positionInCurrentLine = maxPosition >= stat->expandedPosition ? stat->expandedPosition : maxPosition;
  if(stat->positionInCurrentLine < 0) stat->positionInCurrentLine = 0;
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine); 
  return 0;
}

int keyDown(gapBuffer* gb, editorStat* stat){
  if(stat->currentLine + 1 == gb->size) return 0;

  ++stat->currentLine;
   int maxPosition = gapBufferAt(gb, stat->currentLine)->numOfChar-1+(stat->mode == INSERT_MODE);
  stat->positionInCurrentLine = maxPosition >= stat->expandedPosition ? stat->expandedPosition : maxPosition;
  if(stat->positionInCurrentLine < 0) stat->positionInCurrentLine = 0;
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  return 0;
}

int keyRight(gapBuffer* gb, editorStat* stat){
  if(stat->positionInCurrentLine+1 >= gapBufferAt(gb, stat->currentLine)->numOfChar+(stat->mode == INSERT_MODE)) return 0;

  ++stat->positionInCurrentLine;
  stat->expandedPosition = stat->positionInCurrentLine;
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine); 
  return 0;
}



int moveToForwardWord(gapBuffer *gb, editorStat *stat){
  char startWith = gapBufferAt(gb, stat->currentLine)->numOfChar == 0 ? '\n' : gapBufferAt(gb, stat->currentLine)->elements[stat->positionInCurrentLine]; 
  int (*isSkipped)(int) = NULL;
  if(ispunct(startWith)) isSkipped = ispunct;
  else if(isalpha(startWith)) isSkipped = isalpha;
  else if(isdigit(startWith)) isSkipped = isdigit;

  if(isSkipped == NULL){
    gapBufferForward(gb, stat->currentLine, stat->positionInCurrentLine, &stat->currentLine, &stat->positionInCurrentLine);
  }else{
    while(true){
      ++stat->positionInCurrentLine;
      if(stat->positionInCurrentLine >= gapBufferAt(gb, stat->currentLine)->numOfChar){
        ++stat->currentLine;
        stat->positionInCurrentLine = 0;
        break;
      }
      if(!isSkipped(gapBufferAt(gb, stat->currentLine)->elements[stat->positionInCurrentLine])) break;
    }
  }

  while(true){
    if(stat->currentLine >= gb->size){
      stat->currentLine = gb->size-1;
      stat->positionInCurrentLine = gapBufferAt(gb, gb->size-1)->numOfChar-1;
      if(stat->positionInCurrentLine == -1) stat->positionInCurrentLine = 0;
      break;
    }
    if(gapBufferAt(gb, stat->currentLine)->numOfChar == 0) break;
    if(stat->positionInCurrentLine == gapBufferAt(gb, stat->currentLine)->numOfChar){
      ++stat->currentLine;
      stat->positionInCurrentLine = 0;
      continue;
    }
    char curr = gapBufferAt(gb, stat->currentLine)->elements[stat->positionInCurrentLine];
    if(ispunct(curr) || isalpha(curr) || isdigit(curr)) break;
    ++stat->positionInCurrentLine;
  }

  stat->expandedPosition = stat->positionInCurrentLine;
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine); 
  return 0;
}

int keyLeft(gapBuffer* gb, editorStat* stat){
  if(stat->positionInCurrentLine == 0) return 0;
  
  --stat->positionInCurrentLine;
  stat->expandedPosition = stat->positionInCurrentLine;
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine); 
  return 0;
}

int moveToBackwardWord(gapBuffer *gb, editorStat *stat){
  if(gapBufferIsFirst(stat->currentLine, stat->positionInCurrentLine)) return 0;

  while(true){
    gapBufferBackward(gb, stat->currentLine, stat->positionInCurrentLine, &stat->currentLine, &stat->positionInCurrentLine);
    if(gapBufferAt(gb, stat->currentLine)->numOfChar == 0 || gapBufferIsFirst(stat->currentLine, stat->positionInCurrentLine)) break;

    char curr = gapBufferAt(gb, stat->currentLine)->elements[stat->positionInCurrentLine];
    if(isspace(curr)) continue;

    if(stat->positionInCurrentLine == 0) break;

    int backLine, backPosition;
    char back;
    gapBufferBackward(gb, stat->currentLine, stat->positionInCurrentLine, &backLine, &backPosition);
    back = gapBufferAt(gb, backLine)->elements[backPosition];

    int currType = 0, backType = 0;
    if(isalpha(curr)) currType |= 1;
    else if(isdigit(curr)) currType |= 2;
    else if(ispunct(curr)) currType |= 4;
    if(isalpha(back)) backType |= 1;
    else if(isdigit(back)) backType |= 2;
    else if(ispunct(back)) backType |= 4;
    if(currType != backType) break;
  }

  stat->expandedPosition = stat->positionInCurrentLine;
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  return 0;
}

int keyBackspace(gapBuffer* gb, editorStat* stat){
  if(stat->currentLine == 0 && stat->positionInCurrentLine == 0) return 0;

  if(stat->positionInCurrentLine == 0){ // 行の先頭の場合
    stat->positionInCurrentLine = gapBufferAt(gb, stat->currentLine-1)->numOfChar;

    charArray* line = gapBufferAt(gb, stat->currentLine);
    for(int i = 0; i < line->numOfChar; ++i) charArrayPush(gapBufferAt(gb, stat->currentLine-1), line->elements[i]);
    gapBufferDel(gb, stat->currentLine, stat->currentLine+1);
    --stat->currentLine;
  }else{ // 行の途中の文字を削除する場合
    charArrayDel(gapBufferAt(gb, stat->currentLine), stat->positionInCurrentLine-1);
    --stat->positionInCurrentLine;
  }

  reloadEditorView(&stat->view, gb, stat->view.originalLine[0] <= gb->size-1 ? stat->view.originalLine[0] : gb->size-1);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);

  return 0;
}

int insIndent(gapBuffer *gb, editorStat *stat){
  int countSpace = charArrayCountRepeat(gapBufferAt(gb, stat->currentLine), 0, ' ');
  if(countSpace > stat->positionInCurrentLine) countSpace = stat->positionInCurrentLine;
  
  for(int i = 0; i < countSpace; ++i) charArrayPush(gapBufferAt(gb, stat->currentLine+1), ' ');
  return 0;
}

int keyEnter(gapBuffer* gb, editorStat* stat){
  insNewLine(gb, stat, stat->currentLine+1);
  charArray* leftPart = gapBufferAt(gb, stat->currentLine), *rightPart = gapBufferAt(gb, stat->currentLine + 1);
  if(stat->setting.autoIndent == ON){
    insIndent(gb, stat);
    
    int startOfCopy = charArrayCountRepeat(leftPart, 0, ' ');
    if(startOfCopy < stat->positionInCurrentLine) startOfCopy = stat->positionInCurrentLine;
    startOfCopy += charArrayCountRepeat(leftPart, startOfCopy, ' ');
    for(int i = startOfCopy; i < leftPart->numOfChar; ++i) charArrayPush(rightPart, leftPart->elements[i]);
  
    const int popedNum = leftPart->numOfChar-stat->positionInCurrentLine;
    for(int i = 0; i < popedNum; ++i) charArrayPop(leftPart); 
  
    stat->currentLine++;
    stat->positionInCurrentLine = charArrayCountRepeat(rightPart, 0, ' '); 
  }else{
    for(int i = stat->positionInCurrentLine; i < leftPart->numOfChar; ++i) charArrayPush(rightPart, leftPart->elements[i]);
    for(int i = stat->positionInCurrentLine; i < leftPart->numOfChar; ++i) charArrayPop(leftPart);

    stat->currentLine++;
    stat->positionInCurrentLine = 0;
  }
  
  reloadEditorView(&stat->view, gb, stat->view.originalLine[0]);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  stat->numOfChange++;
  return 0;
}

int openBlankLineBelow(gapBuffer *gb, editorStat *stat){
  charArray* blankLine = (charArray*)malloc(sizeof(charArray));
  charArrayInit(blankLine);
  int indent = charArrayCountRepeat(gapBufferAt(gb, stat->currentLine), 0, ' ');
  for(int i=0; i<indent; ++i) charArrayPush(blankLine, ' ');
  gapBufferInsert(gb, blankLine, stat->currentLine+1);

  ++stat->currentLine;
  stat->positionInCurrentLine = indent; 
  
  reloadEditorView(&stat->view, gb, stat->view.originalLine[0]);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  stat->numOfChange++;
  return 0;
}

int openBlankLineAbove(gapBuffer *gb, editorStat *stat){
  charArray *blankLine = (charArray*)malloc(sizeof(charArray));
  charArrayInit(blankLine);
  int indent = charArrayCountRepeat(gapBufferAt(gb, stat->currentLine), 0, ' ');
  for(int i=0; i<indent; ++i) charArrayPush(blankLine, ' ');
  gapBufferInsert(gb, blankLine, stat->currentLine);

  stat->positionInCurrentLine = indent; 

  reloadEditorView(&stat->view, gb, stat->view.originalLine[0]);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  stat->numOfChange++;
  return 0;
}

int appendAfterTheCursor(gapBuffer *gb, editorStat *stat){
  ++stat->positionInCurrentLine;
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  return 0;
}

int appendEndOfLine(gapBuffer *gb, editorStat *stat){
  stat->positionInCurrentLine = gapBufferAt(gb, stat->currentLine)->numOfChar;
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  return 0;
}

int insBeginOfLine(gapBuffer *gb, editorStat *stat){
  stat->positionInCurrentLine = 0;
  stat->cursor.isUpdated = true;
  stat->numOfChange++;
  return 0;
}

int delCurrentChar(gapBuffer *gb, editorStat *stat){
  charArray* line = gapBufferAt(gb, stat->currentLine);
  charArrayDel(line, stat->positionInCurrentLine);
  if(line->numOfChar > 0 && stat->positionInCurrentLine == line->numOfChar) stat->positionInCurrentLine = stat->expandedPosition = line->numOfChar-1;
  reloadEditorView(&stat->view, gb, stat->view.originalLine[0]);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  stat->numOfChange++;
  return 0;
}

int deleteLine(gapBuffer *gb, editorStat *stat, int line){
  gapBufferDel(gb, line, line + 1);

  if(gb->size == 0){
    charArray* emptyLine = (charArray*)malloc(sizeof(charArray));
    if(emptyLine == NULL){
      printf("main: cannot allocated memory...\n");
      return -1;
    }
    charArrayInit(emptyLine);
    gapBufferInsert(gb, emptyLine, 0);
  }
  if(line < stat->currentLine) --stat->currentLine;
  if(stat->currentLine >= gb->size) stat->currentLine = gb->size-1;

  stat->positionInCurrentLine = stat->expandedPosition = 0;

  reloadEditorView(&stat->view, gb, stat->view.originalLine[0] > gb->size-1 ? gb->size-1 : stat->view.originalLine[0]);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  
  stat->numOfChange++;
  return 0;
}

int replaceChar(gapBuffer *gb, editorStat* stat, char ch){
  gapBufferAt(gb, stat->currentLine)->elements[stat->positionInCurrentLine] = ch;
  reloadEditorView(&stat->view, gb, stat->view.originalLine[0]);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  stat->numOfChange++;
  return 0;
}

int moveToFirstLine(gapBuffer *gb, editorStat *stat){
  jumpLine(stat, gb, 0);
  return 0;
}

int moveToLastLine(gapBuffer *gb, editorStat *stat){
  jumpLine(stat, gb, gb->size-1);
  return 0;
}

int insertParen(gapBuffer *gb, editorStat *stat, int ch){
  if(ch == '('){
    charArrayInsert(gapBufferAt(gb, stat->currentLine), ')', stat->positionInCurrentLine);
  }else if(ch == '{'){
    charArrayInsert(gapBufferAt(gb, stat->currentLine), '}', stat->positionInCurrentLine);
  }else if(ch == '"'){
    charArrayInsert(gapBufferAt(gb, stat->currentLine), '"', stat->positionInCurrentLine);
  }else if(ch == '\''){
    charArrayInsert(gapBufferAt(gb, stat->currentLine), '\'', stat->positionInCurrentLine);
  }
  return 0;
}

int insertChar(gapBuffer *gb, editorStat *stat, int key){
  assert(stat->currentLine < gb->size);
  charArrayInsert(gapBufferAt(gb, stat->currentLine), key, stat->positionInCurrentLine);
  ++stat->positionInCurrentLine;

  if(stat->setting.autoCloseParen == ON) insertParen(gb, stat, key);
  
  reloadEditorView(&stat->view, gb, stat->view.originalLine[0]);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  
  stat->numOfChange++;
  return 0;
}

int lineYank(WINDOW **win, gapBuffer *gb, editorStat *stat){
  stat->rgst.numOfYankedLines = stat->cmdLoop > gb->size - stat->currentLine ? gb->size - stat->currentLine : stat->cmdLoop;
  
  for(int line = stat->currentLine; line < stat->currentLine + stat->rgst.numOfYankedLines; line++){
    gapBufferInsert(stat->rgst.yankedLine, charArrayCopy(gapBufferAt(gb, line)), line - stat->currentLine);
  }

  werase(win[CMD_WIN]);
  wprintw(win[CMD_WIN], "%d line yanked", stat->rgst.numOfYankedLines);
  wrefresh(win[CMD_WIN]);
  return 0;
}

int linePaste(gapBuffer *gb, editorStat *stat){
  for(int i=0; i<stat->rgst.numOfYankedLines; i++)
    gapBufferInsert(gb, charArrayCopy(gapBufferAt(stat->rgst.yankedLine, i)) , ++stat->currentLine);

  reloadEditorView(&stat->view, gb, stat->view.originalLine[0] > gb->size-1 ? gb->size-1 : stat->view.originalLine[0]);
  seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
  stat->numOfChange++;
  return 0;
}

int cmdE(gapBuffer *gb, editorStat *stat, char *filename){
  editorStatInit(stat);
  strcpy(stat->filename, filename);
  gapBufferFree(gb);
  gapBufferInit(gb);
  insNewLine(gb, stat, 0);
  openFile(gb, stat);
  return 0;
}

void moveToFirstOfLine(editorStat* stat, gapBuffer* buffer){
  stat->positionInCurrentLine = stat->expandedPosition = 0;
  seekCursor(&stat->view, buffer, stat->currentLine, stat->positionInCurrentLine);
}

void moveToLastOfLine(editorStat* stat, gapBuffer* buffer){
  stat->positionInCurrentLine = gapBufferAt(buffer, stat->currentLine)->numOfChar - 1;
  if(stat->positionInCurrentLine < 0) stat->positionInCurrentLine = 0;
  stat->expandedPosition = stat->positionInCurrentLine;
  seekCursor(&stat->view, buffer, stat->currentLine, stat->positionInCurrentLine);
}

void cmdNormal(WINDOW **win, gapBuffer *gb, editorStat *stat, int key){
  if(stat->cmdLoop == 0) stat->cmdLoop = 1;
  switch(key){
    case KEY_LEFT:
    case 127:   // 127 is backspace key
    case 'h':
      for(int i=0; i<stat->cmdLoop; i++) keyLeft(gb, stat);
      break;
    case 'b':
      for(int i=0; i<stat->cmdLoop; i++) moveToBackwardWord(gb, stat);
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
    case 'w':
      for( int i=0; i<stat->cmdLoop; i++) moveToForwardWord(gb, stat);
      break;
    case KEY_PPAGE:   // Page Up key
    case 2:   // <C-B>
      pageUp(gb, stat);
      break;
    case  KEY_NPAGE:    // Page Down key
    case 6:   // <C-F>
      pageDown(gb, stat);
      break;
    case '0':
    case KEY_HOME:
      moveToFirstOfLine(stat, gb);
      break;
    case '$':
    case KEY_END:
      moveToLastOfLine(stat, gb);
      break;
    case 'g':
      if(wgetch(win[MAIN_WIN]) == 'g') moveToFirstLine(gb, stat);
      else break;
      break;
    case 'G':
      moveToLastLine(gb, stat);
      break;

    case KEY_DC:
    case 'x':
      if(stat->cmdLoop > gapBufferAt(gb,stat->currentLine)->numOfChar - stat->positionInCurrentLine)
        stat->cmdLoop  = gapBufferAt(gb,stat->currentLine)->numOfChar - stat->positionInCurrentLine;
      for(int i=0; i<stat->cmdLoop; i++) delCurrentChar(gb, stat);
      break;
    case 'd':
      if(wgetch(win[MAIN_WIN]) == 'd'){
        if(stat->cmdLoop > gb->size - stat->currentLine)
          stat->cmdLoop = gb->size - stat->currentLine;
        for(int i=0; i<stat->cmdLoop; i++) deleteLine(gb, stat, stat->currentLine);
      }
      break;
    case 'y':
      if(wgetch(win[MAIN_WIN]) == 'y') lineYank(win, gb, stat);
      break;
    case 'p':
      linePaste(gb, stat);
      break;

    case 'r':
      if(stat->cmdLoop > gapBufferAt(gb, stat->currentLine)->numOfChar-stat->positionInCurrentLine) break;
      key = wgetch(win[MAIN_WIN]);
      for(int i = 0; i < stat->cmdLoop; ++i){
        if(i > 0){
          ++stat->positionInCurrentLine;
          stat->expandedPosition = stat->positionInCurrentLine;
          seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
        }
        replaceChar(gb, stat, key);
        
      }
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
      for(int i=0; i<stat->cmdLoop; i++) openBlankLineBelow(gb, stat);
      insertMode(win, gb, stat);
      break;
    case 'O':
      for(int i=0; i<stat->cmdLoop; i++) openBlankLineAbove(gb, stat);
      insertMode(win,gb, stat);
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
    if(stat->view.isUpdated) updateView(&stat->view, win[MAIN_WIN], gb, stat->currentLine);
    if(stat->cursor.isUpdated) updateCursor(&stat->cursor, &stat->view, stat->currentLine, stat->positionInCurrentLine);
    
    wmove(win[MAIN_WIN], stat->cursor.y, stat->view.widthOfLineNum+stat->cursor.x);
    debugMode(win, gb, stat);
    key = wgetch(win[MAIN_WIN]);

    if(key >= '0' && key <= '9'){
      if(stat->cmdLoop > 0){
        stat->cmdLoop *= 10;
        stat->cmdLoop += key - 48;
        if(stat->cmdLoop > 100000) stat->cmdLoop = 100000;
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
    if(stat->view.isUpdated) updateView(&stat->view, win[MAIN_WIN], gb, stat->currentLine);
    if(stat->cursor.isUpdated) updateCursor(&stat->cursor, &stat->view, stat->currentLine, stat->positionInCurrentLine);
    
    wmove(win[MAIN_WIN], stat->cursor.y, stat->view.widthOfLineNum+stat->cursor.x);
    debugMode(win, gb, stat);
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
      case KEY_PPAGE:   // Page Up key
      case 2:   // <C-B>
        pageUp(gb, stat);
        break;
      case  KEY_NPAGE:    // Page Down key
      case 6:   // <C-F>
        pageDown(gb, stat);
        break;
      case KEY_HOME:
        stat->positionInCurrentLine = 0;
        stat->cursor.isUpdated = true;
        break;
      case KEY_END:
        stat->positionInCurrentLine = gapBufferAt(gb, stat->currentLine)->numOfChar;
        stat->cursor.isUpdated = true;
        break;
      case KEY_BACKSPACE:
      case 8:
      case 127:
        keyBackspace(gb, stat);
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
        if(stat->positionInCurrentLine > 0){
          --stat->positionInCurrentLine;
          seekCursor(&stat->view, gb, stat->currentLine, stat->positionInCurrentLine);
        }
        stat->expandedPosition = stat->positionInCurrentLine;
        stat->mode = NORMAL_MODE;
        return;
        break;
      
      default:
        insertChar(gb, stat, key);
    }
  }
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

  if(argc < 2) newFile(gb, stat);
  else{
    strcpy(stat->filename, argv[1]);
    openFile(gb, stat);
  }

  printStatBarInit(win, gb, stat);

  normalMode(win, gb, stat);

  gapBufferFree(gb);
  
  return 0;
}

