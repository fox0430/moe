#include<dirent.h>
#include<ncurses.h>
#include<stdlib.h>
#include<string.h>
#include<unistd.h>
#include<limits.h>
#include"moe.h"

#define FILER_MODE 2
#define MAIN_WIN 0
#define STATE_WIN 1
#define CMD_WIN 2

int printDirEntry(WINDOW *win, struct dirent **nameList, int num, int currentPosi);
void editorStatusInit(editorStatus* status);
int printStatBar(WINDOW *win, gapBuffer *gb, editorStatus *status);
int insNewLine(gapBuffer *gb, editorStatus *status, int position);
int openFile(gapBuffer *gb, editorStatus *status);
int judgeFileOrDir(char *filename);
int exMode(WINDOW **win, gapBuffer *gb, editorStatus *status);

int fileManageMode(WINDOW **win, gapBuffer *gb, editorStatus *status, char *path){
  status->mode = FILER_MODE;
  printStatBar(win[STATE_WIN], gb, status);
  curs_set(0);    // disable cursor;
  struct dirent **nameList;

  char currentPath[PATH_MAX];
  strcpy(currentPath, path);

  int isViewUpdate = true,
      refreshNameList = true,
      currentPosi = 0,
      num,
      key;

  while(1){
    if(refreshNameList == true){
      num = scandir(currentPath, &nameList, NULL, alphasort);
      if(num == -1){
        wprintw(win[CMD_WIN], "File manager: error!");
        return -1;
      }
      currentPosi = 0;
      refreshNameList = false;
      isViewUpdate = true;
    }
    if(isViewUpdate){
      printDirEntry(win[MAIN_WIN], nameList, num, currentPosi);
      isViewUpdate = false;
    }

    key = wgetch(win[MAIN_WIN]);

    switch(key){
      case 'k':
        if(currentPosi > 0){
          --currentPosi;
          isViewUpdate = true;
        }
        break;
      case 'j':
        if(currentPosi < num - 1){
          ++currentPosi;
          isViewUpdate = true;
        }
        break;
      case 'D':
        echo();
        werase(win[CMD_WIN]);
        wprintw(win[CMD_WIN], "delete %s? 'y' or 'n': ", nameList[currentPosi]->d_name);
        nocbreak();
        if(wgetch(win[CMD_WIN]) == 'y'){
          remove(nameList[currentPosi]->d_name);
          werase(win[CMD_WIN]);
          wprintw(win[CMD_WIN], "deleted %s", nameList[currentPosi]->d_name);
          refreshNameList = true;
        }else{
          wgetch(win[CMD_WIN]);   // skip enter key
        }
        cbreak();
        noecho();
        break;
      case 10:    // enter key
          if(currentPosi == 0){
            refreshNameList = true;
          }else if(currentPosi == 1){
            chdir("../");
            getcwd(currentPath, sizeof(path));
            refreshNameList = true;
          }else{
            int result = judgeFileOrDir(nameList[currentPosi]->d_name);
            if(result == 1){
              chdir(nameList[currentPosi]->d_name);
              getcwd(currentPath, sizeof(path));
              free(nameList);
              refreshNameList = true;
            }else{
              char fullPath[PATH_MAX];
              editorStatusInit(status);

              strcpy(fullPath, currentPath);
              strcat(fullPath, nameList[currentPosi]->d_name);
              strcpy(status->filename, nameList[currentPosi]->d_name);

              gapBufferFree(gb);
              gapBufferInit(gb);
              insNewLine(gb, status, 0);
              openFile(gb, status);

              free(nameList);
              curs_set(1);
              return 0;
            }
          }
          break;
      case ':':
       curs_set(1);
       exMode(win, gb, status);
       return 0;
    }
  }
}

void printCurrentEntry(WINDOW *win, char *name){
  wattron(win, A_UNDERLINE);
  wprintw(win, "%s", name);
  if(judgeFileOrDir(name) == 1)
    wprintw(win, "/"); 
  wprintw(win, "\n");
  wattrset(win, A_NORMAL);
}

int printDirEntry(WINDOW *win, struct dirent **nameList, int num, int currentPosi){
  werase(win);
  int start = currentPosi - win->_maxy;
  if(start < 0) start = 0;
  
  for(int i=start, j = 0; i<num;  i++, j++){
    if(j > win->_maxy) break;
    else if(i == currentPosi){
      printCurrentEntry(win, nameList[i]->d_name);
    }else{
      wprintw(win, "%s", nameList[i]->d_name);
      if(judgeFileOrDir(nameList[i]->d_name) == 1)
        wprintw(win, "/"); 
      wprintw(win, "\n");
    }
  }

  wrefresh(win);

  return 0;
}
