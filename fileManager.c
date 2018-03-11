#include<dirent.h>
#include<ncurses.h>
#include<stdlib.h>
#include<string.h>
#include"moe.h"

int getDirInfo(DIR *dir, struct dirent *dp, char *path);

int checkDir(char *path){
  DIR *dir;
  struct dirent *dp;

  if((dir = opendir(path)) == NULL) return -1;
  else getDirInfo(dir , dp, path);

  return 0;
}

int getDirInfo(DIR *dir, struct dirent *dp, char *path){

  gapBuffer *fm = (gapBuffer*)malloc(sizeof(gapBuffer));
  if(fm = NULL){
    printf("file manager: cannot allocated memory.../n");
    return -1;
  }
  gapBufferInit(fm);

  int numDir = 0;
  for(dp = readdir(dir); dp != NULL; dp = readdir(dir), numDir++)
    ;
  char dirName[numDir][256];

  int i = 0;
  for(dp = readdir(dir); i < numDir; dp = readdir(dir)){
    strcpy(dirName[i], dp->d_name);
  }

  closedir(dir);

  return 0;
 }
