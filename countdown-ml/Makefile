# Use the PyTorch solver's environment since the model and the exact search both need PyTorch
TORCH = $(abspath ../countdown-torch)
PYTHON = $(TORCH)/.venv/bin/python

model.pt: train.pt train.py model.py
	$(PYTHON) train.py train.pt $@ 3 256 6

# Leave the PyTorch solver out of the prerequisites since editing it should not force retraining
train.pt: make_data.py tokens.py
	$(MAKE) -C $(TORCH) .venv
	$(PYTHON) make_data.py 3000000 1234 $@

run: model.pt
	$(PYTHON) countdown.py

test: model.pt
	$(PYTHON) -m unittest -v test_solver

.PHONY: run test
