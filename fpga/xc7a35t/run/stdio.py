#!/usr/bin/env python3
import atexit
import os
import sys
import termios


orig_term = None


def stdio_init():
    global orig_term
    atexit.register(stdio_close)
    orig_term = termios.tcgetattr(sys.stdin)
    new_settings = termios.tcgetattr(sys.stdin)
    new_settings[3] = new_settings[3] & ~(termios.ECHO | termios.ICANON)
    new_settings[6][termios.VMIN] = 0
    new_settings[6][termios.VTIME] = 0
    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, new_settings)


def stdio_close():
    global orig_term
    if orig_term:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, orig_term)


def stdio_read():
    ch = os.read(sys.stdin.fileno(), 1)
    if len(ch) > 0:
        return ch
    return None
