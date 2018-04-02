#ifndef MOE_FILEUTILITY_H
#define MOE_FILEUTILITY_H

#include <stdbool.h>

int judgeFileOrDir(char *path);
bool existsFile(char *path);
void expandHomeDirectory(char* path, char* expanded);

#endif
