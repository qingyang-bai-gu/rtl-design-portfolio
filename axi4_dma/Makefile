PYTHON ?= python3
STAGE ?= all
.PHONY: test clean vectors format style lint check

test:
	$(PYTHON) scripts/regress.py --stage $(STAGE)

vectors:
	$(PYTHON) model/planner.py --output build/planner_vectors.txt

format:
	$(PYTHON) scripts/quality.py format

style:
	$(PYTHON) scripts/quality.py style

lint:
	$(PYTHON) scripts/quality.py lint

# Keep these sequential even when invoked with make -j.
check:
	$(PYTHON) scripts/quality.py style
	$(PYTHON) scripts/quality.py lint
	$(PYTHON) scripts/regress.py --stage all

clean:
	rm -rf build
