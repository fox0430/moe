#include<dirent.h>
#include<ncurses.h>
#include<stdlib.h>
#include<string.h>
#include<unistd.h>
#include<limits.h>
#include"moe.h"

int printDirEntry(WINDOW *win, struct dirent **nameList, int num, int currentPosi);
void editorStatusInit(editorStatus* status);
int insNewLine(gapBuffer *gb, editorStatus *status, int position);
int openFile(gapBuffer *gb, editorStatus *status);
int judgeFileOrDir(char *filename);
int exMode(WINDOW **win, gapBuffer *gb, editorStatus *status);

int fileManageMode(WINDOW **win, gapBuffer *gb, editorStatus *status, char *path){
  curs_set(0);    // disable cursor;
  struct dirent **nameList;

  char currentPath[PATH_MAX];
  strcpy(currentPath, path);

  int isViewUpdate = true,
      moveDir = true,
      currentPosi = 0,
      num,
      key;

  while(1){
    if(moveDir == true){
      num = scandir(currentPath, &nameList, NULL, alphasort);
      if(num == -1){
        wprintw(win[2], "File manager: error!");
        return -1;
      }
      currentPosi = 0;
      moveDir = false;
      isViewUpdate = true;
    }
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
          if(currentPosi == 0){
            moveDir = true;
          }else if(currentPosi == 1){
            chdir("../");
            getcwd(currentPath, sizeof(path));
            moveDir = true;
          }else{
            int result = judgeFileOrDir(nameList[currentPosi]->d_name);
            if(result == 1){
              chdir(nameList[currentPosi]->d_name);
              getcwd(currentPath, sizeof(path));
              free(nameList);
              moveDir = true;
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

int printDirEntry(WINDOW *win, struct dirent **nameList, int num, int currentPosi){
  werase(win);
  int start = currentPosi - win->_maxy;
  if(start < 0) start = 0;
  
  for(int i=start, j = 0; i<num;  i++, j++){
    if(j > win->_maxy) break;
    else if(i == currentPosi){
      wattron(win, A_UNDERLINE);
      wprintw(win, "%s\n", nameList[i]->d_name);
      wattrset(win, A_NORMAL);
    }else wprintw(win, "%s\n", nameList[i]->d_name);
  }

  wrefresh(win);

  return 0;
}
