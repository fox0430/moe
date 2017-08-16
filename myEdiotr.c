/*
	I do not know windows. You should use UNIX like operaing system.
*/

#include<stdio.h>
#include<string.h>
#include<stdlib.h>
#include<ncurses.h>


#define KEY_ESC 27
#define MAX_FILE_NAME 255
const int LINE_NUM_SPACE = 2;

typedef struct _textInfo{
	char *str;						
	int lineMax;				// max line number
	int *numOfchar;			// all char
} txt;


void createBackUp(char *filename){      // I am not confident of this program... :(

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
	char *str = NULL;

	if(fopen(filename, "r") == NULL){   // file open
		printf("%s Cannot file open... \n", filename);
		exit(0);
  }else{
		createBackUp(filename);
	}

	fp = fopen(filename, "r");

// streck file size

	fseek(fp, 0, SEEK_END);	
	size = ftell(fp);
	fseek(fp, 0, SEEK_SET);

	if ((str = malloc(size)) == NULL){
		printf("cannot allocate memory... \n");
		exit(0);
	}

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
		printw("%c", *(str+i));		// display char
		i++;

	}

	return 0;

}


void insertChar(char *str, int key, int y, int x){

	char *tmp = NULL;
	int i = 0, c = 0;

	if ((tmp = (char*)realloc(str, (sizeof(char)+strlen(str)))) == NULL){
		printf("cannot allocate memory...\n");
		exit(0);
	}else{
		str = tmp;
	}

	while(i != y){		// search insert position
		if (*(str+c) == '\n'){
			i++;
		}
		c++;
	}



}

int insertKeys(char *str){

	int key, y = 0, x = LINE_NUM_SPACE;

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
				if (y == 0) break;
				y--;
				break;

			case KEY_DOWN:
				y++;
				break;

			case KEY_RIGHT:
				x++;
				break;

			case KEY_LEFT:
				if (x == LINE_NUM_SPACE) break;
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
				insertChar(str, key, y, x);
		
		}
	}
}

void startCurses(){

	int h, w;
	initscr();      // start terminal contorl 
	curs_set(1);    //set cursr
	keypad(stdscr, TRUE);   //enable cursr keys

	getmaxyx(stdscr, h, w);     // set window size
	scrollok(stdscr, TRUE);			// enable scroll

	start_color();      // color settings 
	init_pair(1, COLOR_WHITE, COLOR_BLACK);     // set color strar is white and back is black
	init_pair(2, COLOR_GREEN, COLOR_BLACK);
	bkgd(COLOR_PAIR(1));    // set default color

	erase();	// screen display 

	ESCDELAY = 25;      // delete esc key time lag

	move(0, 0);     // set default cursr point

}

int main(int argc, char *argv[]){

	txt content = {NULL, 0, 0};

	if (argc < 2){
		printf("Please text file");
		return -1;
  }

	content.str = openFile(argv[1]);

	startCurses();

	printChar(content.str);

	insertKeys(content.str);

	endwin();	// exit curses 

	return 0;

}
