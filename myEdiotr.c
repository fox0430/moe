#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<ncurses.h>


#define KEY_ESC 27
#define MAX_FILE_NAME 255


void createBackUp(char* filename){      // I am not confident of this program... :(

  if ((sizeof(filename)+12) > MAX_FILE_NAME){
      return;     // can not create backup file
  }

// excute cp command

  char cmd[MAX_FILE_NAME] = {'c', 'p', ' ',};
  strcat(cmd, filename);
  strcat(cmd, " ");
  strcat(cmd, filename);
  strcat(cmd, ".backup");
  system(cmd);

}

char* openFile(char* filename){

	FILE *fp;
	int size, i = 0;

  if(fopen(filename, "r") == NULL){   // file open
   	printf("%s Cannot allocate memory \n", filename);
		exit(0);
  }

	fp = fopen(filename, "r");

// check file size

	fseek(fp, 0, SEEK_END);	
	size = ftell(fp);
	fseek(fp, 0, SEEK_SET);

	char *str = malloc(size);

	while ((*(str+i) = fgetc(fp)) != EOF) {
		i++;
  }

	fclose(fp);

  return str;

}

int printChar(char *str){
	
	int lineNum = 1, i = 0;

	bkgd(COLOR_PAIR(2));
	printw("%d:", i+1);

	while (*(str+i+1) != EOF){

		refresh();

		if (*(str+i-1) == '\n'){

			bkgd(COLOR_PAIR(2));
			lineNum++;
			printw("%d:", lineNum);			// display line number

		}

		bkgd(COLOR_PAIR(1));
		printw("%c", *(str+i));
		i++;

	}

	return 0;

}

int insertKeys(){

	int key, y = 0, x = 2;

	move(x, y);

	while(1){

		move(y, x);
		refresh();
		noecho();			// no display keys;
		key = getch();		// get keys

		if (key == KEY_ESC){
			break;
		}

		switch(key){

			case KEY_UP:
				y--;
				break;

			case KEY_DOWN:
				y++;
				break;

			case KEY_RIGHT:
				x++;
				break;

			case KEY_LEFT:
				x--;
				break;

			case KEY_BACKSPACE:
				delch();
				move(y, x--);
				break;

			default:
				echo();			// display keys
				bkgd(COLOR_PAIR(1));
				insch(key);
		
		}
	}
}

void startCurses(){

	int h, w;
	initscr();      // start terminal contorl 
	curs_set(1);    //set cursr
 	keypad(stdscr, TRUE);   //enable cursr keys

  getmaxyx(stdscr, h, w);     // set window size

	start_color();      // color settings 
 	init_pair(1, COLOR_WHITE, COLOR_BLACK);     // set color char is white and back is black
	init_pair(2, COLOR_GREEN, COLOR_BLACK);
  bkgd(COLOR_PAIR(1));    // set default color

  erase();	// screen display 

  ESCDELAY = 25;      // delete esc key time lag

  move(0, 0);     // set default cursr point

}

int main(int argc, char *argv[]){

	char *str;

 	if (argc < 2){
		printf("Please text file");
		return -1;
  }

	str = openFile(argv[1]);
 	createBackUp(argv[1]);     //create backup file	

	startCurses();

	printChar(str);

	insertKeys();

  endwin();	// exit curses 

  return 0;

}
