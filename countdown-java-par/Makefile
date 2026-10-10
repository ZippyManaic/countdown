SOURCES = $(wildcard src/countdownpar/*.java)

build: $(SOURCES)
	javac -d out $(SOURCES)
	touch build

test: build
	java -cp out countdownpar.ParSolverTest

run: build
	java -cp out countdownpar.Countdown

clean:
	rm -rf out build

.PHONY: test run clean
