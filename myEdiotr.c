#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<ncurses.h>

const int LineMax = 999;
const int KEY_ESC = 27;

int main(int argc, char *argv[]){

    if (argc < 2){
        printf("Please text file");
        return -1;
    }

    FILE *fp;
    char fname[strlen(argv[1])+1];
    strcpy(fname,argv[1]);
    int h, w, i, key, ch, displayLineNumber;
    int x, y = 0;
    char *readLine = malloc(sizeof(char) *1 * 1); 
    
    ESCDELAY = 25;      // delete esc time lag
    
    initscr();      // start terminal contorl 
    curs_set(1);    //set cursr
    keypad(stdscr, TRUE);   //enable cursr keys

    getmaxyx(stdscr, h, w);     // set window size

    start_color();      // color settings 
    init_pair(1, COLOR_WHITE, COLOR_BLACK);     // set color. 1 is white and black
    init_pair(2, COLOR_GREEN, COLOR_BLACK);
    bkgd(COLOR_PAIR(1));    // set default color


    fp = fopen( fname, "r" );   // file open
    if( fp == NULL ){

        printf( "%s can not file open \n", fname );
        return -1;
    }

    erase();	// screen display 
    move(0, 0);     // set default cursr point

    i = 1;  // line number
    while (( ch = fgetc(fp)) != EOF ) {     // display char

        refresh();

        if (displayLineNumber == true || i == 1){   //display line number

            bkgd(COLOR_PAIR(2));    // color set
            printw("%d: ",i);
            displayLineNumber = false;
            i++;
        }

        bkgd(COLOR_PAIR(1));
        printw("%c",ch);

        if (ch == '\n'){
            displayLineNumber = true;
        }
    }

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

    endwin();	// exit control 
    return (0);
}
