#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <unistd.h>
#include <pwd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include "fileutility.h"

int judgeFileOrDir(char *path){
  struct stat st;
  stat(path, &st);

  if(S_ISREG(st.st_mode)) return 1; // regular file
  else if(S_ISDIR(st.st_mode)) return 2; // directory
  else return 0; // other
}

bool existsFile(char* path){
  struct stat st;

  if(stat(path, &st) != 0){
    return false;
  }

  return S_ISREG(st.st_mode);
}

char* homeDirectory(){
  char* homeDir;
  if ((homeDir = getenv("HOME")) == NULL) {
    homeDir = getpwuid(getuid())->pw_dir;
  }
  return homeDir;
}

void expandHomeDirectory(char* path, char* expanded){
  char* homeDir = homeDirectory();
  snprintf(expanded, PATH_MAX, "%s%s", homeDir, path+1);
}
