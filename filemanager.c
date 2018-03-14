#include<dirent.h>
#include<ncurses.h>
#include<stdlib.h>
#include<string.h>
#include "moe.h"

int printDirEntry(WINDOW *win, struct dirent **nameList, int num, int currentPosi);
void editorStatusInit(editorStatus* status);
int insNewLine(gapBuffer *gb, editorStatus *status, int position);
int openFile(gapBuffer *gb, editorStatus *status);
int judgeFileOrDir(char *filename);
int exMode(WINDOW **win, gapBuffer *gb, editorStatus *status);

int fileManageMode(WINDOW **win, gapBuffer *gb, editorStatus *status, char *path){
  curs_set(0);    // disable cursor;
  struct dirent **nameList;

  int num = scandir(path, &nameList, NULL, alphasort);
  if(num == -1){
    wprintw(win[2], "File manager: error!");
    return -1;
  }

  int isViewUpdate = true,
      currentPosi = 0,
      key;

  while(1){
    if(isViewUpdate){
      printDirEntry(win[0], nameList, num, currentPosi);
      isViewUpdate = false;
    }

    key = wgetch(win[0]);

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
      case 10:    // enter key
        {
          int result = judgeFileOrDir(nameList[currentPosi]->d_name);
          if(result == 1){
            free(nameList);
            num = scandir(path, &nameList, NULL, alphasort);
            if(num == -1){
              wprintw(win[2], "File manager: error!");
              return -1;
            }
            isViewUpdate = true;
          }else{
            editorStatusInit(status);
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
      case ':':
       curs_set(1);
       exMode(win, gb, status);
       return 0;
    }
  }
}

int printDirEntry(WINDOW *win, struct dirent **nameList, int num, int currentPosi){
  werase(win);
  for(int i=0; i<num; i++)
    if(i == currentPosi){
      wattron(win, A_UNDERLINE);
      wprintw(win, "%s\n", nameList[i]->d_name);
      wattrset(win, A_NORMAL);
    }else wprintw(win, "%s\n", nameList[i]->d_name);

  wrefresh(win);

  return 0;
}
