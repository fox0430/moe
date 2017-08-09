#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<ncurses.h>
#include<malloc.h>

#define KEY_ESC 27
#define MAX_FILE_NAME 255

int *countChar;
int LINEMAX = 0;
int debg = 0;

void createBackUp(char* filename){      // I am not confident of this program... :(

    if ((sizeof(filename)+12) > MAX_FILE_NAME){
        return;     // can not create backup file
        }

    char cmd[MAX_FILE_NAME] = {'c', 'p', ' ',};
    strcat(cmd, filename);
    strcat(cmd, " ");
    strcat(cmd, filename);
    strcat(cmd, ".backup");
    system(cmd);
}

int openFile(FILE **fp, char* filename){

    if(fopen(filename, "r+") == NULL){   // file open
        printf( "%s can not file open \n", filename);
        return -1;
    }

    *fp = fopen(filename,"r+");
}

char** readFile(char *filename){

    FILE *fp, *fo;
    int i = 0, j = 0, ch;
    char **readLine;
    countChar = malloc(sizeof(int *)*30);
    readLine = malloc(sizeof(char *)*30);
    readLine[i] = malloc(sizeof(char)*50);

    openFile(&fp, filename);    // open file

    bkgd(COLOR_PAIR(2));
    printw("1: ");

    while ((ch = fgetc(fp)) != EOF) {     // display char

        refresh();

        if (ch == '\n'){
		    i++;
		    j = 0;
    	    bkgd(COLOR_PAIR(2));
    	    printw("\n%d: ",i+1);
            readLine = (char**)realloc(readLine, (i+1)*sizeof(char*));
            countChar = (int*)realloc(countChar, (i)*sizeof(int*));
    	}else{
   	        if(j == 0){
                readLine[i] = (char*)malloc(1);
                    if(readLine[i] == NULL){
            	        printf("Failed to do malloc in LINE%d. \n",i);
            	        return NULL;
            }
        }else{
                
            char* tmp = (char*)realloc(readLine[i], (j+1)*sizeof(char));
                if(tmp == NULL){
                     printf( "Failed to do realloc in LINE%d. \n",i+1);
                     return NULL;
                }
        readLine[i] = tmp;
        LINEMAX = i;
        }

        readLine[i][j] = ch;
        bkgd(COLOR_PAIR(1));
        printw("%c",readLine[i][j]);
        ++j;
        countChar[i] = j;
        }
    }
    return readLine;
}

//////////////////////////////////
/////////////CAUTION!//////////////
/////////////////////////////////

void charInsert(int x, int y, char **readLine, int key){    /* insert keys. DO NOT COMPLITE. copy extra char... */        

        int i = y;  // low
        int j = 0;
        int jTmp = x-3;
        int c = 0;
        debg = y;

        char* tmp = (char*)realloc(readLine[i], (countChar[i]+1)*sizeof(char));
        for (j = countChar[i]-jTmp; j > jTmp-1; j--){    // doubtful...
            tmp[j+1] = tmp[j];
        }
        readLine[j] = tmp;
        readLine[i][jTmp] = key;
        LINEMAX = j;
}

int main(int argc, char *argv[]){

    if (argc < 2){
        printf("Please text file");
        return -1;
    }

    FILE *fp;
    char filename[strlen(argv[1])+1];
    strcpy(filename,argv[1]);
    int h, w, key, ch, displayLineNumber = 0;
    int x = 0, y = 0;
    char **readLine;

    createBackUp(filename);     //create backup file

    ESCDELAY = 25;      // delete esc key time lag
    
    initscr();      // start terminal contorl 
    curs_set(1);    //set cursr
    keypad(stdscr, TRUE);   //enable cursr keys

    getmaxyx(stdscr, h, w);     // set window size

    start_color();      // color settings 
    init_pair(1, COLOR_WHITE, COLOR_BLACK);     // set color char is white and back is black
    init_pair(2, COLOR_GREEN, COLOR_BLACK);
    bkgd(COLOR_PAIR(1));    // set default color

    erase();	// screen display 

    readLine = readFile(filename);

    move(0, 0);     // set default cursr point

    bkgd(COLOR_PAIR(2));    // color set

    x = 3, y = 0;
    move(x, y);

    while (1) {     // input keys

        move(y, x);
        refresh();
        noecho();
        key = getch();

        if (key == KEY_ESC){
            break;
        }

        if (key == KEY_BACKSPACE) {
            delch();
            move(x--, y);
        }

        switch (key) {

            case KEY_UP:   
                if (y == 0) break;
                if (countChar[y-1]+3 <= x) break;
                y--; break; 

            case KEY_DOWN:
                if (y == LINEMAX) break;
                if (countChar[y+1]+3 <= x) break; 
                y++;
                break;

            case KEY_LEFT:
                if (x == 3){
                    break;
                }
                x--;
                break;

            case KEY_RIGHT:
                if (countChar[y]+2 == x){
                    break;
                }
                x++;
                break;
            default:
                echo();
                bkgd(COLOR_PAIR(1));
                insch(key);
                charInsert(x, y, readLine, key);
		}
	}

    endwin();	// exit control 

    printf("%s\n", readLine[0]);
    printf("%s\n", readLine[1]);
    printf("%s\n", readLine[2]);
    printf("%d\n", countChar[0]);
    printf("%d\n", countChar[1]);
    printf("%d\n", countChar[2]);
    printf("%d\n", debg);

    return 0;
}
