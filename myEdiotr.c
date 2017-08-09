#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<ncurses.h>
#include<malloc.h>

const int KEY_ESC = 27;

/*
int openFile(FILE **fp, char* filename){

    if(fopen(filename, "r+") == NULL){   // file open
        printf( "%s can not file open \n", filename);
        return -1;
    }
    *fp = fopen(filename,"r+");
}
*/

char** readFile(char *filename){

    FILE *fp;
    int i = 0, j = 0, ch;
    char **readLine;
    readLine = malloc(sizeof(char *)*30);
    readLine[i] = malloc(sizeof(char)*50);

    fp = fopen( filename, "r" );   // file open
    if( fp == NULL ){

        printf( "%s can not file open \n", filename );
        return NULL;
    }

    bkgd(COLOR_PAIR(2));
    printw("1: ");

    while (( ch = fgetc(fp)) != EOF ) {     // display char

        refresh();

        if (ch == '\n'){
		    i++;
		    j = 0;
    	    bkgd(COLOR_PAIR(2));
    	    printw("\n%d: ",i+1);
    		//readLine = (char**)realloc(readLine, i*sizeof(char*));
            readLine = (char**)realloc(readLine, (i+1)*sizeof(char*));
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
            }
            readLine[i][j] = ch;
            bkgd(COLOR_PAIR(1));
            printw("%c",readLine[i][j]);
            ++j;
        }
    }
    return readLine;
}

int main(int argc, char *argv[]){

    if (argc < 2){
        printf("Please text file");
        return -1;
    }

    FILE *fp;
    char filename[strlen(argv[1])+1];
    strcpy(filename,argv[1]);
    int h, w, i, j = 0, key, ch, displayLineNumber = 0;
    int x = 0, y = 0;
    char **readLine;

    ESCDELAY = 25;      // delete esc key time lag
    
    initscr();      // start terminal contorl 
    curs_set(1);    //set cursr
    keypad(stdscr, TRUE);   //enable cursr keys

    getmaxyx(stdscr, h, w);     // set window size

    start_color();      // color settings 
    init_pair(1, COLOR_WHITE, COLOR_BLACK);     // set color char is white and back is black
    init_pair(2, COLOR_GREEN, COLOR_BLACK);
    bkgd(COLOR_PAIR(1));    // set default color

//    openFile(&fp, filename); // open file read only

    erase();	// screen display 

    readLine = readFile(filename);

/*
    fp = fopen( fname, "r" );   // file open
    if( fp == NULL ){

        printf( "%s can not file open \n", fname );
        return -1;
    }
*/
    move(0, 0);     // set default cursr point

    bkgd(COLOR_PAIR(2));    // color set

/*    
    printw("1: ");
    
    while (( ch = fgetc(fp)) != EOF ) {     // display char

        refresh();

        if (ch == '\n'){
            i++;
            j = 0;
            bkgd(COLOR_PAIR(2));    // color set
            printw("\n%d: ",i+1);
            readLine = (char**)realloc(readLine, i*sizeof(char*));
        }else{
          	if(j == 0){
                readLine[i] = (char*)malloc(1);
                if (readLine[i] == NULL){
                    printf("Failed to do malloc in LINE%d. \n",i);
                    return -1;
                }
            }else{
              char* tmp = (char*)realloc(readLine[i], (j+1)*sizeof(char));
              if(tmp == NULL){
                printf( "Failed to reallocate ew memory space in LINE%d. \n",i+1);
                return -1;
                }
                readLine[i] = tmp;
            }
            readLine[i][j] = ch;
            bkgd(COLOR_PAIR(1));
            printw("%c",readLine[i][j]);
            ++j;
            }
        }
        fclose(fp);
*/
    move(0, 0);

    while (1) {     // input keys

        move(y, x);
        refresh();

        key = getch();

        if (key == KEY_ESC) break;
        if (key == KEY_BACKSPACE) {
            delch();
            move(x--, y);
        }

        switch (key) {
            case KEY_UP: y--; break;
            case KEY_DOWN: y++; break;
            case KEY_LEFT: x--; break;
            case KEY_RIGHT: x++; break;
		}
	}

/*    
    for (int k=0; k<c; k++){
        free(readLine[k]);
    }

    free(readLine);
*/

    endwin();	// exit control 

    return 0;
}
