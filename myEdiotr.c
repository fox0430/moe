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


typedef struct textInfo_t {
	char *str;
	int numOfLine;			// max line number
	int numOfchar;			// number of all char
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

txt* openFile(char* filename){

	FILE *fp;
	int size, i = 0;

	if(fopen(filename, "r") == NULL){   // file open
		printf("%s Cannot file open... \n", filename);
		exit(0);
  }else{
		createBackUp(filename);
	}

	fp = fopen(filename, "r");

// check file size

	txt *content = malloc(sizeof(txt));

	fseek(fp, 0, SEEK_END);	
	size = ftell(fp);
	fseek(fp, 0, SEEK_SET);

	if ((content->str = malloc(size)) == NULL){
		printf("cannot allocate memory... \n");
		exit(0);
	}

	while ((*(content->str+i) = fgetc(fp)) != EOF) {
		if(content->str[i] == '\n') ++content->numOfLine;
		content->numOfchar++;
		i++;
	}

	fclose(fp);
	
	return content;

}

int printStr(char *str){
	
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

void printTxt(txt* content){
	int lineNum = 0;
	bkgd(COLOR_PAIR(2));
	printw("1:");
	for(int i = 0; i<content->numOfchar; ++i){
		printw("%c",content->str[i]);
		if(content->str[i] == '\n'){
			++lineNum;
			printw("%d:", lineNum+1);
		}
	}
}

//seek specified position
int seekTxt(txt* content, int y, int x){
	int i = 0,c = 0;
	while(i != y){
		if (*(content->str+c) == '\n'){
			i++;
		}
		c++;
	}

	for(i=0; i<(x-LINE_NUM_SPACE); i++){
		c++;
	}
	return c;
}

txt* insertChar(txt* content, int key, int y, int x){

	char *tmp = NULL;
	int i = 0, c = seekTxt(content,y,x);

	if ((tmp = (char*)realloc(content->str, sizeof(char)*(strlen(content->str)+1))) == NULL){
		printf("cannot allocate memory...\n");
		exit(0);
	}else{
		content->str = tmp;
	}

	// insert char
	for(i=content->numOfchar; i>=(c-1); i--){
		*(content->str+(i+1)) = *(content->str+i);
	}
	*(content->str+(c)) = key;

	content->numOfchar++;

	return content;
}

txt* eraseChar(txt* content, int y, int x){
	int erasedCharIndex = seekTxt(content, y, x);
	//shift
	for(int i = erasedCharIndex; i+1<content->numOfchar; ++i) content->str[i] = content->str[i+1];

	char *tmp=NULL;
	if((tmp = (char*)realloc(content->str,sizeof(char)*(strlen(content->str)-1))) == NULL){
		printf("cannot allocate memory...\n");
		exit(0);
	}else{
		content->str = tmp;
	}

	return content;
}

txt* insertKeys(txt* content){

	int key, y = 0, x = LINE_NUM_SPACE;

	move(x, y);

	while(1){

		move(y, x);
		refresh();
		noecho();			// no display keys;
		key = getch();		// get keys

		if(key == KEY_ESC){
			break;
		}
		
		switch(key){

			case KEY_UP:
				if (y == 0) break;
				y--;
				break;

			case KEY_DOWN:
				if(y == content->numOfLine) break;
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
				if(x == LINE_NUM_SPACE) break;
				--x;
				move(y, x);
				delch();
				eraseChar(content, y, x);
				break;

			default:
				echo();			// display keys
				bkgd(COLOR_PAIR(1));
				insch(key);
				insertChar(content, key, y, x);
		
		}
	}

	return content;
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

	if (argc < 2){
		printf("Please text file");
		return -1;
	}

	txt* content = openFile(argv[1]);

	startCurses();

	printTxt(content);

	insertKeys(content);

	endwin();	// exit curses 

// debug

	int i = 0;
	while(*(content->str+i) != EOF){
		printf("%c", *(content->str+i));
		i++;
	}

	return 0;

}
