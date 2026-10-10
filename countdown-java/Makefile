SOURCES = $(wildcard src/countdown/*.java)

build: $(SOURCES)
	javac -d out $(SOURCES)
	touch build

test: build
	java -cp out countdown.SolverTest

run: build
	java -cp out countdown.Countdown

clean:
	rm -rf out build

.PHONY: test run clean
