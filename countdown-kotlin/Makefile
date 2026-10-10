SOURCES = $(wildcard src/countdown/*.kt)

build: countdown.jar

countdown.jar: $(SOURCES)
	kotlinc $(SOURCES) -include-runtime -d countdown.jar

test: countdown.jar
	java -cp countdown.jar countdown.SolverTest

run: countdown.jar
	java -cp countdown.jar countdown.CountdownKt

clean:
	rm -f countdown.jar

.PHONY: build test run clean
