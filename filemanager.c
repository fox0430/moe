#include<dirent.h>
#include<ncurses.h>
#include<stdlib.h>
#include "moe.h"

int printDirEntry(WINDOW *win, struct dirent **nameList, int num, int currentPosi);

int fileManageMode(WINDOW **win, editorStatus *status, char *path){
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
      default:
        free(nameList);
        curs_set(1);
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
