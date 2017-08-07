#include <ncurses.h>
#include<stdio.h>
#include<string.h>

int main(int argc,char *argv[]){

    FILE *fp;
    char fname[strlen(argv[1])+1];
    strcpy(fname,argv[1]);
    int c, h, w, key;
    int x, y = 0;
    

	initscr();      // start terminal contorl 
    curs_set(1);    //set cursr
    keypad(stdscr, TRUE);   //enable cursr keys

	getmaxyx(stdscr, h, w);     // set window size

	start_color();      // color settings 
	init_pair(1, COLOR_GREEN, COLOR_BLACK);     // set color. 1 is white and black
	bkgd(COLOR_PAIR(1));    // set default color


    fp = fopen( fname, "r" );   // file open
    if( fp == NULL ){
        printf( "%s can not file oprn \n", fname );
    return -1;
    }

	erase();	// screen display 
	move(0, 0);     // set default cursr point

    while( (c = fgetc( fp )) != EOF ){      // display file contents
        printw( "%c", c );
	    refresh();
    }


    while (1) {     // input keys

		move(y, x);
		refresh();

		key = getch();
		if (key == 'q') break;

        switch (key) {
		case KEY_UP:	y--; break;
		case KEY_DOWN:	y++; break;
		case KEY_LEFT:	x--; break;
		case KEY_RIGHT:	x++; break;
        default: echo(); x++;
		}
	}

	endwin();	// exit contorl 
	return (0);
}
