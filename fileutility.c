#include <sys/stat.h>
#include "fileutility.h"

int judgeFileOrDir(char *filename){
  struct stat st;
  stat(filename, &st);

  if(S_ISREG(st.st_mode)) return 1; // regular file
  else if(S_ISDIR(st.st_mode)) return 2; // directory
  else return 0; // other
}

bool existsFile(char* path){
  struct stat st;

  if (stat(path, &st) != 0){
      return false;
  }

  return S_ISREG(st.st_mode);
}
