#include "mathutility.h"

int countDigit(int num){
  int digit = 0;
  while(num > 0){
    ++digit;
    num /= 10;
  }
  return digit;
}
