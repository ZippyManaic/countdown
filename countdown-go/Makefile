# Target x86-64-v3 so the compiler can use BMI2 shifts and popcnt in the solver's hot loops
export GOAMD64 = v3

countdown: *.go go.mod
	go build -o $@ .

test:
	go test ./...

clean:
	rm -f countdown

.PHONY: test clean
