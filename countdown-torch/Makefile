# Keep PyTorch in a local virtual environment since it is too large to install system-wide
PYTHON = .venv/bin/python

.venv:
	python3 -m venv .venv
	$(PYTHON) -m pip install -q -r requirements.txt

run: .venv
	$(PYTHON) countdown.py

test: .venv
	$(PYTHON) -m unittest -v test_solver

.PHONY: run test
