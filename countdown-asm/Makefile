countdown: main.o solver.o
	ld -o $@ main.o solver.o

%.o: %.s
	as -o $@ $<

clean:
	rm -f countdown *.o

.PHONY: clean
