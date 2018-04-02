#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <malloc.h>
#include <signal.h>
#include <ncurses.h>
#include <ctype.h>
#include <limits.h>
#include <unistd.h>
#include <regex.h>
#include "moe.h"
#include "mathutility.h"
#include "filemanager.h"
#include "fileutility.h"

#define KEY_ESC 27
#define COLOR_DEFAULT -1
#define BRIGHT_WHITE 231
#define BRIGHT_GREEN 85
#define LIGHT_BLUE 14
#define GRAY 245
#define ON 1
#define OFF 0
#define NORMAL_MODE 0
#define INSERT_MODE 1
#define FILER_MODE 2
#define MAIN_WIN 0
#define STATE_WIN 1
#define CMD_WIN 2

int registersInit(editorStatus *status);
int cmdE(WINDOW **win, gapBuffer *gb, editorStatus *status, char *filename);
int insertChar(gapBuffer *gb, editorStatus *status, int key);
void insertMode(WINDOW **win, gapBuffer* gb, editorStatus* status);
void editorSettingInit(editorStatus *status);

int debugMode(WINDOW **win, gapBuffer *gb, editorStatus *status){
#ifdef DEBUG
  int returnY = status->cursor.y,returnX = status->cursor.x;
  werase(win[CMD_WIN]);
  mvwprintw(win[CMD_WIN], 0, 0, "debug mode: ");
  wprintw(win[CMD_WIN], "currentLine: %d ", status->currentLine);
  wprintw(win[CMD_WIN], "numOfLines: %d ", gb->size);
  wprintw(win[CMD_WIN], "numOfChar: %d ", gapBufferAt(gb, status->currentLine)->numOfChar);
  wprintw(win[CMD_WIN], "change: %d ", status->numOfChange);
  wprintw(win[CMD_WIN], "cursor: %d ", status->positionInCurrentLine);
  wprintw(win[CMD_WIN], "elements: %s", gapBufferAt(gb, status->currentLine)->elements);
//  wprintw(win[CMD_WIN], "numOfYankedLines: %d", status->rgst.numOfYankedLines);
//  wprintw(win[CMD_WIN], "yanked elements: %s", gapBufferAt(status->rgst.yankedLine, 0)->elements);
  wrefresh(win[CMD_WIN]);
  wmove(win[MAIN_WIN], returnY, returnX+status->view.widthOfLineNum);
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
  init_pair(8, LIGHT_BLUE, COLOR_DEFAULT);
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

int openFile(gapBuffer *gb, editorStatus *status){
  FILE *fp = fopen(status->filename, "r");
  if(fp != NULL){
    char  ch;
    while((ch = fgetc(fp)) != EOF){
      if(ch=='\n'){
        status->currentLine += 1;
        charArray* ca = (charArray*)malloc(sizeof(charArray));
        if(ca == NULL){
          printf("main read file: cannot allocated memory...\n");
          return -1;
        }
        charArrayInit(ca);
        gapBufferInsert(gb, ca, status->currentLine);
      }else charArrayPush(gapBufferAt(gb, status->currentLine), ch);
    }
    fclose(fp);
  }
  
  status->currentLine = status->positionInCurrentLine = status->expandedPosition = 0;
  status->cursor.isUpdated = true;
  freeEditorView(&status->view);
  initEditorView(&status->view, gb, &status->cursor, LINES-2, COLS-(countDigit(gb->size+1)+1)-1);
  return 0;
}

int newFile(gapBuffer *gb, editorStatus *status){
  status->currentLine = status->positionInCurrentLine = 0;
  status->cursor.isUpdated = true;
  initEditorView(&status->view, gb, &status->cursor, LINES-2, COLS-(countDigit(gb->size+1)+1)-1);
  return 0;
}

void winResizeEvent(WINDOW **win, gapBuffer *gb, editorStatus *status){
  endwin(); 
  initscr();
  winResizeMove(win[MAIN_WIN], LINES-2, COLS, 0, 0);
  winResizeMove(win[STATE_WIN], 1, COLS, LINES-2, 0);
  winResizeMove(win[CMD_WIN], 1, COLS, LINES-1, 0);
  if(status->mode != FILER_MODE){
    resizeEditorView(&status->view, gb, LINES-2, COLS-status->view.widthOfLineNum-1, status->view.widthOfLineNum);
    seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  }
  printStatBarInit(win[STATE_WIN], gb, status);
}

void editorStatusInit(editorStatus* status){
  status->currentLine = 0;
  status->positionInCurrentLine = 0;
  status->expandedPosition = 0;
  status->mode = NORMAL_MODE;
  status->cmdLoop = 0;
  strcpy(status->filename, "No name");
  getcwd(status->currentDir, PATH_MAX);
  status->numOfChange = 0;
  status->debugMode = OFF;
  registersInit(status);
  editorSettingInit(status);
}

int registersInit(editorStatus *status){
  status->rgst.yankedLine = (gapBuffer*)malloc(sizeof(gapBuffer));
  if(status->rgst.yankedLine == NULL){
    printf("main register: cannot allocated memory...\n");
    return -1;
  }
  gapBufferInit(status->rgst.yankedLine);
  insNewLine(status->rgst.yankedLine, status, 0);
  status->rgst.yankedStr = (charArray*)malloc(sizeof(charArray));
  if(status->rgst.yankedStr == NULL){
    printf("main register: cannot allocated memory...\n");
    return -1;
  }
  charArrayInit(status->rgst.yankedStr);
  status->rgst.numOfYankedLines = 0;
  status->rgst.numOfYankedStr = 0;

  return 0;
}

void editorSettingInit(editorStatus *status){
  status->setting.autoCloseParen = ON;
  status->setting.autoIndent = ON;
  status->setting.tabStop = 2;
}

int saveFile(WINDOW **win, gapBuffer* gb, editorStatus *status){

  if(strcmp(status->filename, "No name") == 0){
    int   i = 0;
    char  ch, 
          filename[NAME_MAX];
    wattron(win[CMD_WIN], COLOR_PAIR(4));
    werase(win[CMD_WIN]);
    wprintw(win[CMD_WIN], "Please input file name: ");
    wrefresh(win[CMD_WIN]);
    wattron(win[CMD_WIN], COLOR_PAIR(3));
    echo();
    while(1){
      if((ch = wgetch(win[CMD_WIN])) == 10 || i > NAME_MAX) break;
      filename[i] = ch;
      i++;
    }
    noecho();
    strcpy(status->filename, filename);
    werase(win[CMD_WIN]);
  }
  
  FILE *fp;
  if ((fp = fopen(status->filename, "w")) == NULL) {
    printf("%s Cannot open the file... \n", status->filename);
      return -1;
    }
  
  for(int i=0; i < gb->size; i++){
    fprintf(fp, "%s\n",gapBufferAt(gb, i)->elements);
  }

  mvwprintw(win[CMD_WIN], 0, 0, "saved..., %d times changed", status->numOfChange);
  wrefresh(win[CMD_WIN]);

  fclose(fp);
  status->numOfChange = 0;

  return 0;
}

void printStatBarInit(WINDOW *win, gapBuffer *gb, editorStatus *status){
  werase(win);
  wbkgd(win, COLOR_PAIR(1));
  printStatBar(win, gb, status);
}

int printStatBar(WINDOW *win, gapBuffer *gb, editorStatus *status){
  werase(win);
  wattron(win, COLOR_PAIR(2));
  if(status->mode == FILER_MODE){
    wprintw(win, "%s ", " FILER");
    wattron(win, COLOR_PAIR(1));
    wrefresh(win);
    return 0;
  }
  if(status->mode == NORMAL_MODE)
    wprintw(win, "%s ", " NORMAL");
  else if(status->mode == INSERT_MODE)
    wprintw(win, "%s ", " INSERT");
  wattron(win, COLOR_PAIR(1));
  wprintw(win, " %s ", status->filename);
  if(strcmp(status->filename, "No name") == 0) wprintw(win, " [+]");
  mvwprintw(win, 0, COLS-13, "%d/%d ", status->currentLine + 1, gb->size);
  mvwprintw(win, 0, COLS-6, " %d/%d", status->positionInCurrentLine, gapBufferAt(gb, status->currentLine)->numOfChar);
  wrefresh(win);
  return 0;
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

int jumpLine(editorStatus* status, gapBuffer* buffer, int destination){
  editorView* view = &status->view;
  int currentLine = status->currentLine;
  status->currentLine = destination;
  status->positionInCurrentLine = status->expandedPosition = 0;
  if(!(view->originalLine[0] <= destination && (view->originalLine[view->height-1] == -1 || destination <= view->originalLine[view->height-1]))){
    int startOfPrintedLines = destination-(currentLine - view->originalLine[0]) >= 0 ?  destination-(currentLine - view->originalLine[0]) : 0;
    reloadEditorView(view, buffer, startOfPrintedLines);
  }
  seekCursor(&status->view, buffer, status->currentLine, status->positionInCurrentLine);
  return 0;
}

int pageUp(gapBuffer *buffer, editorStatus *status){
  int destination = status->currentLine - status->view.height;
  if(destination < 0) destination = 0;
  jumpLine(status, buffer, destination);
  return 0;
}

int pageDown(gapBuffer *buffer, editorStatus *status){
  int destination = status->currentLine + status->view.height;
  if(destination > buffer->size - 1) destination = buffer->size - 1;
  jumpLine(status, buffer, destination);
  return 0;
}

int parseCmdEString(char* cmd, char* path){
  regex_t preg;
  const char* pattern = "^e(([[:blank:]]+)\"(.+)\"(.*))|(([[:blank:]]+)([^ ]+)(.*))$";
  const size_t num = 8;
  regmatch_t pmatch[num]; // 正規表現にマッチしたインデックスを格納する構造体の配列

  // 正規表現のコンパイル
  if(regcomp(&preg, pattern, REG_EXTENDED|REG_NEWLINE) != 0){
    assert(false);
    return -1;
  }

  // 正規表現による検索
  if(regexec(&preg, cmd, num, pmatch, 0) != 0) {
    assert(false);
    return -1;
  }else{
    int begin, end;
    if(pmatch[3].rm_so != -1){ // quoted
      begin = pmatch[3].rm_so;
      end = pmatch[3].rm_eo;
    }else{ // not quoted
      begin = pmatch[7].rm_so;
      end = pmatch[7].rm_eo;
    }
    for(int i=begin; i<end; ++i){
        path[i-begin]=cmd[i];
    }
    path[end-begin]='\0';
  }
  // オブジェクトのメモリ開放
  regfree(&preg);

  return 0;
}

int exMode(WINDOW **win, gapBuffer *gb, editorStatus *status){
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
      jumpLine(status, gb,  lineNum);
      return 0;
    }else if(cmd[i] == 'w'){
      saveFile(win, gb, status);
      saveFlag = true;
    }else if(cmd[i] == 'q'){
      if(cmd[i + 1] == '!' || status->numOfChange == 0) exitCurses();
      else if(cmd[i + 1] != '!'){
        if(status->numOfChange > 0 && saveFlag != true){
          printNoWriteError(win[CMD_WIN]);
        }
      }
    }else if(cmd[0] == 'e'){  // open file or dir
      if(strlen(cmd) < 3){
        werase(win[CMD_WIN]);
        wattron(win[CMD_WIN], COLOR_PAIR(4));
        wprintw(win[CMD_WIN], "%S", "Error: cannot open this file or dir");
        wrefresh(win[CMD_WIN]);
        wattroff(win[CMD_WIN], COLOR_PAIR(4));
      }else{
        char parsed[PATH_MAX];
        if(parseCmdEString(cmd, parsed) == -1 || strlen(parsed) == 0) return 0; // failed to parse or empty input

        char* filename;
        if(parsed[0] == '~'){
          char expanded[PATH_MAX];
          expandHomeDirectory(parsed, expanded);
          filename = expanded;
        }else filename = parsed;

        cmdE(win, gb, status, filename);
        break;
      }
    }else if(cmd[0] == '!'){    // Shell command execution
      shellMode(cmd);
      werase(win[CMD_WIN]);
      wrefresh(win[CMD_WIN]);
    }
  }
  return 0;
}

void printNoWriteError(WINDOW* win){
  wattron(win, COLOR_PAIR(4));
  werase(win);
  wprintw(win, "%s","Erorr: No write since last change");
  wrefresh(win);
  wattroff(win, COLOR_PAIR(4));
}

int insNewLine(gapBuffer *gb, editorStatus *status, int position){
  charArray* ca = (charArray*)malloc(sizeof(charArray));
  if(ca == NULL){
    printf("main insert new line: cannot allocated memory...\n");
    return -1;
  }
  charArrayInit(ca);
  gapBufferInsert(gb, ca, position);
  return 0;
}

int insertTab(gapBuffer *gb, editorStatus *status){
  for(int i=0; i<status->setting.tabStop; i++)
    insertChar(gb, status, ' ');
  return 0;
}

int keyUp(gapBuffer* gb, editorStatus* status){
  if(status->currentLine == 0) return 0;
 
  --status->currentLine;
  int maxPosition = gapBufferAt(gb, status->currentLine)->numOfChar-1+(status->mode == INSERT_MODE);
  status->positionInCurrentLine = maxPosition >= status->expandedPosition ? status->expandedPosition : maxPosition;
  if(status->positionInCurrentLine < 0) status->positionInCurrentLine = 0;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine); 
  return 0;
}

int keyDown(gapBuffer* gb, editorStatus* status){
  if(status->currentLine + 1 == gb->size) return 0;

  ++status->currentLine;
   int maxPosition = gapBufferAt(gb, status->currentLine)->numOfChar-1+(status->mode == INSERT_MODE);
  status->positionInCurrentLine = maxPosition >= status->expandedPosition ? status->expandedPosition : maxPosition;
  if(status->positionInCurrentLine < 0) status->positionInCurrentLine = 0;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  return 0;
}

int keyRight(gapBuffer* gb, editorStatus* status){
  if(status->positionInCurrentLine+1 >= gapBufferAt(gb, status->currentLine)->numOfChar+(status->mode == INSERT_MODE)) return 0;

  ++status->positionInCurrentLine;
  status->expandedPosition = status->positionInCurrentLine;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine); 
  return 0;
}



int moveToForwardWord(gapBuffer *gb, editorStatus *status){
  char startWith = gapBufferAt(gb, status->currentLine)->numOfChar == 0 ? '\n' : gapBufferAt(gb, status->currentLine)->elements[status->positionInCurrentLine]; 
  int (*isSkipped)(int) = NULL;
  if(ispunct(startWith)) isSkipped = ispunct;
  else if(isalpha(startWith)) isSkipped = isalpha;
  else if(isdigit(startWith)) isSkipped = isdigit;

  if(isSkipped == NULL){
    gapBufferForward(gb, status->currentLine, status->positionInCurrentLine, &status->currentLine, &status->positionInCurrentLine);
  }else{
    while(true){
      ++status->positionInCurrentLine;
      if(status->positionInCurrentLine >= gapBufferAt(gb, status->currentLine)->numOfChar){
        ++status->currentLine;
        status->positionInCurrentLine = 0;
        break;
      }
      if(!isSkipped(gapBufferAt(gb, status->currentLine)->elements[status->positionInCurrentLine])) break;
    }
  }

  while(true){
    if(status->currentLine >= gb->size){
      status->currentLine = gb->size-1;
      status->positionInCurrentLine = gapBufferAt(gb, gb->size-1)->numOfChar-1;
      if(status->positionInCurrentLine == -1) status->positionInCurrentLine = 0;
      break;
    }
    if(gapBufferAt(gb, status->currentLine)->numOfChar == 0) break;
    if(status->positionInCurrentLine == gapBufferAt(gb, status->currentLine)->numOfChar){
      ++status->currentLine;
      status->positionInCurrentLine = 0;
      continue;
    }
    char curr = gapBufferAt(gb, status->currentLine)->elements[status->positionInCurrentLine];
    if(ispunct(curr) || isalpha(curr) || isdigit(curr)) break;
    ++status->positionInCurrentLine;
  }

  status->expandedPosition = status->positionInCurrentLine;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine); 
  return 0;
}

int keyLeft(gapBuffer* gb, editorStatus* status){
  if(status->positionInCurrentLine == 0) return 0;
  
  --status->positionInCurrentLine;
  status->expandedPosition = status->positionInCurrentLine;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine); 
  return 0;
}

int moveToBackwardWord(gapBuffer *gb, editorStatus *status){
  if(gapBufferIsFirst(status->currentLine, status->positionInCurrentLine)) return 0;

  while(true){
    gapBufferBackward(gb, status->currentLine, status->positionInCurrentLine, &status->currentLine, &status->positionInCurrentLine);
    if(gapBufferAt(gb, status->currentLine)->numOfChar == 0 || gapBufferIsFirst(status->currentLine, status->positionInCurrentLine)) break;

    char curr = gapBufferAt(gb, status->currentLine)->elements[status->positionInCurrentLine];
    if(isspace(curr)) continue;

    if(status->positionInCurrentLine == 0) break;

    int backLine, backPosition;
    char back;
    gapBufferBackward(gb, status->currentLine, status->positionInCurrentLine, &backLine, &backPosition);
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

  status->expandedPosition = status->positionInCurrentLine;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  return 0;
}

int keyBackspace(gapBuffer* gb, editorStatus* status){
  if(status->currentLine == 0 && status->positionInCurrentLine == 0) return 0;

  if(status->positionInCurrentLine == 0){ // 行の先頭の場合
    status->positionInCurrentLine = gapBufferAt(gb, status->currentLine-1)->numOfChar;

    charArray* line = gapBufferAt(gb, status->currentLine);
    for(int i = 0; i < line->numOfChar; ++i) charArrayPush(gapBufferAt(gb, status->currentLine-1), line->elements[i]);
    gapBufferDel(gb, status->currentLine, status->currentLine+1);
    --status->currentLine;
  }else{ // 行の途中の文字を削除する場合
    charArrayDel(gapBufferAt(gb, status->currentLine), status->positionInCurrentLine-1);
    --status->positionInCurrentLine;
  }

  reloadEditorView(&status->view, gb, status->view.originalLine[0] <= gb->size-1 ? status->view.originalLine[0] : gb->size-1);
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);

  return 0;
}

int insIndent(gapBuffer *gb, editorStatus *status){
  int countSpace = charArrayCountRepeat(gapBufferAt(gb, status->currentLine), 0, ' ');
  if(countSpace > status->positionInCurrentLine) countSpace = status->positionInCurrentLine;
  
  for(int i = 0; i < countSpace; ++i) charArrayPush(gapBufferAt(gb, status->currentLine+1), ' ');
  return 0;
}

int keyEnter(gapBuffer* gb, editorStatus* status){
  insNewLine(gb, status, status->currentLine+1);
  charArray* leftPart = gapBufferAt(gb, status->currentLine), *rightPart = gapBufferAt(gb, status->currentLine + 1);
  if(status->setting.autoIndent == ON){
    insIndent(gb, status);
    
    int startOfCopy = charArrayCountRepeat(leftPart, 0, ' ');
    if(startOfCopy < status->positionInCurrentLine) startOfCopy = status->positionInCurrentLine;
    startOfCopy += charArrayCountRepeat(leftPart, startOfCopy, ' ');
    for(int i = startOfCopy; i < leftPart->numOfChar; ++i) charArrayPush(rightPart, leftPart->elements[i]);
  
    const int popedNum = leftPart->numOfChar-status->positionInCurrentLine;
    for(int i = 0; i < popedNum; ++i) charArrayPop(leftPart); 
  
    status->currentLine++;
    status->positionInCurrentLine = charArrayCountRepeat(rightPart, 0, ' '); 
  }else{
    for(int i = status->positionInCurrentLine; i < leftPart->numOfChar; ++i) charArrayPush(rightPart, leftPart->elements[i]);
    for(int i = status->positionInCurrentLine; i < leftPart->numOfChar; ++i) charArrayPop(leftPart);

    status->currentLine++;
    status->positionInCurrentLine = 0;
  }
  
  reloadEditorView(&status->view, gb, status->view.originalLine[0]);
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  status->numOfChange++;
  return 0;
}

int openBlankLineBelow(gapBuffer *gb, editorStatus *status){
  charArray* blankLine = (charArray*)malloc(sizeof(charArray));
  charArrayInit(blankLine);
  int indent = charArrayCountRepeat(gapBufferAt(gb, status->currentLine), 0, ' ');
  for(int i=0; i<indent; ++i) charArrayPush(blankLine, ' ');
  gapBufferInsert(gb, blankLine, status->currentLine+1);

  ++status->currentLine;
  status->positionInCurrentLine = indent; 
  
  reloadEditorView(&status->view, gb, status->view.originalLine[0]);
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  status->numOfChange++;
  return 0;
}

int openBlankLineAbove(gapBuffer *gb, editorStatus *status){
  charArray *blankLine = (charArray*)malloc(sizeof(charArray));
  charArrayInit(blankLine);
  int indent = charArrayCountRepeat(gapBufferAt(gb, status->currentLine), 0, ' ');
  for(int i=0; i<indent; ++i) charArrayPush(blankLine, ' ');
  gapBufferInsert(gb, blankLine, status->currentLine);

  status->positionInCurrentLine = indent; 

  reloadEditorView(&status->view, gb, status->view.originalLine[0]);
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  status->numOfChange++;
  return 0;
}

int appendAfterTheCursor(gapBuffer *gb, editorStatus *status){
  ++status->positionInCurrentLine;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  return 0;
}

int appendEndOfLine(gapBuffer *gb, editorStatus *status){
  status->positionInCurrentLine = gapBufferAt(gb, status->currentLine)->numOfChar;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  return 0;
}

int insBeginOfLine(gapBuffer *gb, editorStatus *status){
  status->positionInCurrentLine = 0;
  status->cursor.isUpdated = true;
  status->numOfChange++;
  return 0;
}

int delCurrentChar(gapBuffer *gb, editorStatus *status){
  charArray* line = gapBufferAt(gb, status->currentLine);
  charArrayDel(line, status->positionInCurrentLine);
  if(line->numOfChar > 0 && status->positionInCurrentLine == line->numOfChar) status->positionInCurrentLine = status->expandedPosition = line->numOfChar-1;
  reloadEditorView(&status->view, gb, status->view.originalLine[0]);
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  status->numOfChange++;
  return 0;
}

int deleteLine(gapBuffer *gb, editorStatus *status, int line){
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
  if(line < status->currentLine) --status->currentLine;
  if(status->currentLine >= gb->size) status->currentLine = gb->size-1;

  status->positionInCurrentLine = status->expandedPosition = 0;

  reloadEditorView(&status->view, gb, status->view.originalLine[0] > gb->size-1 ? gb->size-1 : status->view.originalLine[0]);
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  
  status->numOfChange++;
  return 0;
}

int replaceChar(gapBuffer *gb, editorStatus* status, char ch){
  gapBufferAt(gb, status->currentLine)->elements[status->positionInCurrentLine] = ch;
  reloadEditorView(&status->view, gb, status->view.originalLine[0]);
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  status->numOfChange++;
  return 0;
}

int moveFirstLine(gapBuffer *gb, editorStatus *status){
  if(status->currentLine == 0) return 0;
  status->currentLine = 0;
  int maxPosition = gapBufferAt(gb, status->currentLine)->numOfChar-1+(status->mode == INSERT_MODE);
  status->positionInCurrentLine  = maxPosition >= status->expandedPosition ? status->expandedPosition : maxPosition;
  if(status->positionInCurrentLine < 0) status->positionInCurrentLine = 0;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine); 
  return 0;
}

int moveLastLine(gapBuffer *gb, editorStatus *status){
  if(status->currentLine == gb->size - 1) return 0;
  status->currentLine = gb->size - 1;
  int maxPosition = gapBufferAt(gb, status->currentLine)->numOfChar-1+(status->mode == INSERT_MODE);
  status->positionInCurrentLine = maxPosition >= status->expandedPosition ? status->expandedPosition : maxPosition;
  if(status->positionInCurrentLine < 0) status->positionInCurrentLine = 0;
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine); 
  return 0;
}

int insertParen(gapBuffer *gb, editorStatus *status, int ch){
  if(ch == '('){
    charArrayInsert(gapBufferAt(gb, status->currentLine), ')', status->positionInCurrentLine);
  }else if(ch == '{'){
    charArrayInsert(gapBufferAt(gb, status->currentLine), '}', status->positionInCurrentLine);
  }else if(ch == '"'){
    charArrayInsert(gapBufferAt(gb, status->currentLine), '"', status->positionInCurrentLine);
  }else if(ch == '\''){
    charArrayInsert(gapBufferAt(gb, status->currentLine), '\'', status->positionInCurrentLine);
  }
  return 0;
}

int insertChar(gapBuffer *gb, editorStatus *status, int key){
  assert(status->currentLine < gb->size);
  charArrayInsert(gapBufferAt(gb, status->currentLine), key, status->positionInCurrentLine);
  ++status->positionInCurrentLine;

  if(status->setting.autoCloseParen == ON) insertParen(gb, status, key);
  
  reloadEditorView(&status->view, gb, status->view.originalLine[0]);
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  
  status->numOfChange++;
  return 0;
}

int lineYank(WINDOW **win, gapBuffer *gb, editorStatus *status){
  status->rgst.numOfYankedLines = status->cmdLoop > gb->size - status->currentLine ? gb->size - status->currentLine : status->cmdLoop;
  
  for(int line = status->currentLine; line < status->currentLine + status->rgst.numOfYankedLines; line++){
    gapBufferInsert(status->rgst.yankedLine, charArrayCopy(gapBufferAt(gb, line)), line - status->currentLine);
  }

  werase(win[CMD_WIN]);
  wprintw(win[CMD_WIN], "%d line yanked", status->rgst.numOfYankedLines);
  wrefresh(win[CMD_WIN]);
  return 0;
}

int linePaste(gapBuffer *gb, editorStatus *status){
  for(int i=0; i<status->rgst.numOfYankedLines; i++)
    gapBufferInsert(gb, charArrayCopy(gapBufferAt(status->rgst.yankedLine, i)) , ++status->currentLine);

  reloadEditorView(&status->view, gb, status->view.originalLine[0] > gb->size-1 ? gb->size-1 : status->view.originalLine[0]);
  seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  status->numOfChange++;
  return 0;
}

int cmdE(WINDOW **win, gapBuffer *gb, editorStatus *status, char *filename){
  int fileOrDir = judgeFileOrDir(filename);

  if(fileOrDir == 2){   // open file manager
    noecho();
    fileManageMode(win, gb, status, filename);
    noecho();
    status->view.isUpdated = true;
    seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
  }else if(!existsFile(filename) || fileOrDir == 1){ // regular file or new file
    if(status->numOfChange > 0){
      printNoWriteError(win[CMD_WIN]);
      return 0;
    }
    editorStatusInit(status);
    strcpy(status->filename, filename);
    gapBufferFree(gb);
    gapBufferInit(gb);
    insNewLine(gb, status, 0);
    openFile(gb, status);
  }
  return 0;
}

void moveToFirstOfLine(editorStatus* status, gapBuffer* buffer){
  status->positionInCurrentLine = status->expandedPosition = 0;
  seekCursor(&status->view, buffer, status->currentLine, status->positionInCurrentLine);
}

void moveToLastOfLine(editorStatus* status, gapBuffer* buffer){
  status->positionInCurrentLine = gapBufferAt(buffer, status->currentLine)->numOfChar - 1;
  if(status->positionInCurrentLine < 0) status->positionInCurrentLine = 0;
  status->expandedPosition = status->positionInCurrentLine;
  seekCursor(&status->view, buffer, status->currentLine, status->positionInCurrentLine);
}

void cmdNormal(WINDOW **win, gapBuffer *gb, editorStatus *status, int key){
  if(status->cmdLoop == 0) status->cmdLoop = 1;
  switch(key){
    case KEY_LEFT:
    case 127:   // 127 is backspace key
    case 'h':
      for(int i=0; i<status->cmdLoop; i++) keyLeft(gb, status);
      break;
    case 'b':
      for(int i=0; i<status->cmdLoop; i++) moveToBackwardWord(gb, status);
      break;
    case KEY_DOWN:
    case 10:    // 10 is Enter key
    case 'j':
      for(int i=0; i<status->cmdLoop; i++) keyDown(gb, status);
     break;
    case KEY_UP:
    case 'k':
      for(int i=0; i<status->cmdLoop; i++) keyUp(gb, status);
      break;
    case KEY_RIGHT:
    case 'l':
      for(int i=0; i<status->cmdLoop; i++) keyRight(gb, status);
      break;
    case 'w':
      for( int i=0; i<status->cmdLoop; i++) moveToForwardWord(gb, status);
      break;
    case KEY_PPAGE:   // Page Up key
    case 2:   // <C-B>
      pageUp(gb, status);
      break;
    case  KEY_NPAGE:    // Page Down key
    case 6:   // <C-F>
      pageDown(gb, status);
      break;
    case '0':
    case KEY_HOME:
      moveToFirstOfLine(status, gb);
      break;
    case '$':
    case KEY_END:
      moveToLastOfLine(status, gb);
      break;
    case 'g':
      if(wgetch(win[MAIN_WIN]) == 'g') moveFirstLine(gb, status);
      else break;
      break;
    case 'G':
      moveLastLine(gb, status);
      break;

    case KEY_DC:
    case 'x':
      if(status->cmdLoop > gapBufferAt(gb,status->currentLine)->numOfChar - status->positionInCurrentLine)
        status->cmdLoop  = gapBufferAt(gb,status->currentLine)->numOfChar - status->positionInCurrentLine;
      for(int i=0; i<status->cmdLoop; i++) delCurrentChar(gb, status);
      break;
    case 'd':
      if(wgetch(win[MAIN_WIN]) == 'd'){
        if(status->cmdLoop > gb->size - status->currentLine)
          status->cmdLoop = gb->size - status->currentLine;
        for(int i=0; i<status->cmdLoop; i++) deleteLine(gb, status, status->currentLine);
      }
      break;
    case 'y':
      if(wgetch(win[MAIN_WIN]) == 'y') lineYank(win, gb, status);
      break;
    case 'p':
      linePaste(gb, status);
      break;

    case 'r':
      if(status->cmdLoop > gapBufferAt(gb, status->currentLine)->numOfChar-status->positionInCurrentLine) break;
      key = wgetch(win[MAIN_WIN]);
      for(int i = 0; i < status->cmdLoop; ++i){
        if(i > 0){
          ++status->positionInCurrentLine;
          status->expandedPosition = status->positionInCurrentLine;
          seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
        }
        replaceChar(gb, status, key);
        
      }
      break;
    case 'a':
      appendAfterTheCursor(gb, status);
      insertMode(win, gb, status);
      break;
    case 'A':
      appendEndOfLine(gb, status);
      insertMode(win, gb, status);
      break;
    case 'I':
      insBeginOfLine(gb, status);
      insertMode(win, gb, status);
      break;
    case 'o':
      for(int i=0; i<status->cmdLoop; i++) openBlankLineBelow(gb, status);
      insertMode(win, gb, status);
      break;
    case 'O':
      for(int i=0; i<status->cmdLoop; i++) openBlankLineAbove(gb, status);
      insertMode(win,gb, status);
      break;
    case 'i':
      insertMode(win, gb, status);
      break;
  }
}

void normalMode(WINDOW **win, gapBuffer *gb, editorStatus *status){
  int key;
  status->cmdLoop = 0;
  status->mode = NORMAL_MODE;
  noecho();

  while(1){
    printStatBar(win[STATE_WIN], gb, status); 
    if(status->view.isUpdated) updateView(&status->view, win[MAIN_WIN], gb, status->currentLine);
    if(status->cursor.isUpdated) updateCursor(&status->cursor, &status->view, status->currentLine, status->positionInCurrentLine);
    
    wmove(win[MAIN_WIN], status->cursor.y, status->view.widthOfLineNum + status->cursor.x);
    debugMode(win, gb, status);
    key = wgetch(win[MAIN_WIN]);

    if(key >= '0' && key <= '9'){
      if(status->cmdLoop > 0){
        status->cmdLoop *= 10;
        status->cmdLoop += key - 48;
        if(status->cmdLoop > 100000) status->cmdLoop = 100000;
      }else{
        if(key == '0') cmdNormal(win, gb, status, key);
        else status->cmdLoop = key - 48;
      }
    }
    else if(key == KEY_ESC) status->cmdLoop = 0;
    else if(key == KEY_RESIZE) winResizeEvent(win, gb, status);
    else if(key == ':') exMode(win, gb, status);
    else{
      cmdNormal(win, gb, status, key);
      status->cmdLoop = 0;
    }
  }
}

void insertMode(WINDOW **win, gapBuffer* gb, editorStatus* status){
  int key;
  status->mode = INSERT_MODE;
  noecho();

  while(1){
    printStatBar(win[STATE_WIN], gb, status);
    if(status->view.isUpdated) updateView(&status->view, win[MAIN_WIN], gb, status->currentLine);
    if(status->cursor.isUpdated) updateCursor(&status->cursor, &status->view, status->currentLine, status->positionInCurrentLine);
    
    wmove(win[MAIN_WIN], status->cursor.y, status->view.widthOfLineNum + status->cursor.x);
    debugMode(win, gb, status);
    key = wgetch(win[MAIN_WIN]);

    switch(key){
      case KEY_UP:
        keyUp(gb, status);
        break;
      case KEY_DOWN:
        keyDown(gb, status);
        break;
      case KEY_RIGHT:
        keyRight(gb, status);
        break;
      case KEY_LEFT:
        keyLeft(gb, status);
        break;
      case KEY_PPAGE:   // Page Up key
      case 2:   // <C-B>
        pageUp(gb, status);
        break;
      case  KEY_NPAGE:    // Page Down key
      case 6:   // <C-F>
        pageDown(gb, status);
        break;
      case KEY_HOME:
        status->positionInCurrentLine = 0;
        status->cursor.isUpdated = true;
        break;
      case KEY_END:
        status->positionInCurrentLine = gapBufferAt(gb, status->currentLine)->numOfChar;
        status->cursor.isUpdated = true;
        break;
      case KEY_BACKSPACE:
      case 8:
      case 127:
        keyBackspace(gb, status);
        break;
      case KEY_DC:
        delCurrentChar(gb, status);
        break;

      case 10:    // 10 is Enter key
        keyEnter(gb, status);
        break;

      case 9:   // 9 is Tab key;
        insertTab(gb, status);
        break;

      case KEY_RESIZE:
        winResizeEvent(win, gb, status);
        break;
      case KEY_ESC:
        if(status->positionInCurrentLine > 0){
          --status->positionInCurrentLine;
          seekCursor(&status->view, gb, status->currentLine, status->positionInCurrentLine);
        }
        status->expandedPosition = status->positionInCurrentLine;
        status->mode = NORMAL_MODE;
        return;
        break;
      
      default:
        insertChar(gb, status, key);
    }
  }
}

int main(int argc, char* argv[]){

  editorStatus *status = (editorStatus*)malloc(sizeof(editorStatus));
  if(status == NULL){
    printf("main: cannot allocated memory...\n");
    return -1;
  }
  editorStatusInit(status);

  gapBuffer *gb = (gapBuffer*)malloc(sizeof(gapBuffer));
  if(gb == NULL){
    printf("main: cannot allocated memory...\n");
    return -1;
  }
  gapBufferInit(gb);
  insNewLine(gb, status, 0);

  WINDOW **win = (WINDOW**)malloc(sizeof(WINDOW*)*3);
  if(signal(SIGINT, signal_handler) == SIG_ERR ||
     signal(SIGQUIT, signal_handler) == SIG_ERR){
      fprintf(stderr, "signal failure\n");
      exit(EXIT_FAILURE);
  }

  startCurses(status);
  winInit(win);
  printStatBarInit(win[STATE_WIN], gb, status);

  if(argc < 2) newFile(gb, status);
  else{
    if(judgeFileOrDir(argv[1]) == 2){
      noecho();
      fileManageMode(win, gb, status, argv[1]);
      echo();
    }else{
      strcpy(status->filename, argv[1]);
      openFile(gb, status);
    }
  }

  normalMode(win, gb, status);

  gapBufferFree(gb);
  
  return 0;
}

