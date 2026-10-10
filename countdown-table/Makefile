# Build the table with the PyTorch solver since solving all 8.5 million rounds takes it about three minutes
TORCH = $(abspath ../countdown-torch)

# Leave the PyTorch solver out of the prerequisites since editing it should not force a three-minute rebuild
answers.bin: build_table.py pools.py
	$(MAKE) -C $(TORCH) .venv
	$(TORCH)/.venv/bin/python build_table.py $@

run: answers.bin
	python3 countdown.py

test: answers.bin
	python3 -m unittest -v test_solver

.PHONY: run test
