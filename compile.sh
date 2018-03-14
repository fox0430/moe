#!/bin/sh
gcc -o moe chararray.c gapbuffer.c mathutility.c view.c cursor.c filemanager.c moe.c -lncurses -Wall 
