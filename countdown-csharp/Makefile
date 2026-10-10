build:
	dotnet build -c Release --nologo -v q Countdown

test:
	dotnet run -c Release --project Countdown.Tests

run: build
	./Countdown/bin/Release/net10.0/Countdown

clean:
	rm -rf Countdown/bin Countdown/obj Countdown.Tests/bin Countdown.Tests/obj

.PHONY: build test run clean
