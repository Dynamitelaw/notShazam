CC = g++
CXX = g++

INCLUDES =

CFLAGS = -g -Wall $(INCLUDES)
CXXFLAGS = -g -Wall $(INCLUDES) -std=c++0x

LDFLAGS = -g
LDLIBS =

executables = recognize
objects = recognize.o

.PHONY: default
default: $(executables)

$(objects):

.PHONY: clean
clean :
	rm -rf *.o recognize

.PHONY: all
all: clean default
