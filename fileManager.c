#include<dirent.h>
#include<ncurses.h>
#include<stdlib.h>
#include"moe.h"

int printDirEntry(WINDOW *win, struct dirent **nameList, int num);

int fileManageMode(WINDOW **win, char *path){
  struct dirent **nameList;

  int num = scandir(path, &nameList, NULL, alphasort);
  if(num == -1){
    wprintw(win[2], "not found...");
    return -1;
  }
 
  printDirEntry(win[0], nameList, num);

  free(nameList);
  
  return 0;
}

int printDirEntry(WINDOW *win, struct dirent **nameList, int num){
  werase(win);
  for(int i=0; i<num; i++)
    wprintw(win, " %s\n", nameList[i]->d_name);

  return 0;
}
