FPC = fpc
FPCFLAGS ?= -O3 -CpCOREAVX2 -OpCOREAVX2 -vewn

countdown: countdown.pas dealer.pas solver.pas
	$(FPC) $(FPCFLAGS) countdown.pas

test: tests.pas dealer.pas solver.pas
	$(FPC) $(FPCFLAGS) tests.pas
	./tests

clean:
	rm -f countdown tests *.o *.ppu

.PHONY: test clean
