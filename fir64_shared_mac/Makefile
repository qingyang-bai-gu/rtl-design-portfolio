PYTHON ?= python3
MATLAB ?= matlab
VCD ?= build/gate_activity.vcd

.PHONY: test vectors check-vectors activity synth synth-mapped gate-activity sta power matlab compare-matlab clean

test:
	$(PYTHON) scripts/regress.py

vectors:
	$(PYTHON) model/reference.py

check-vectors:
	$(PYTHON) model/reference.py --check

activity:
	$(PYTHON) scripts/regress.py --vcd
	$(PYTHON) -m unittest discover -s scripts -p 'test_*.py' -v
	$(PYTHON) scripts/activity.py build/activity.vcd --out build/activity.json

synth:
	$(PYTHON) scripts/synthesize.py

synth-mapped:
	$(PYTHON) scripts/synthesize.py --liberty "$(LIBERTY)"

gate-activity:
	$(PYTHON) scripts/gate_activity.py --cells "$(CELL_MODELS)"

sta:
	$(PYTHON) scripts/run_sta.py --liberty "$(LIBERTY)"

power:
	$(PYTHON) scripts/run_sta.py --liberty "$(LIBERTY)" --vcd "$(VCD)"

matlab:
	"$(MATLAB)" -batch "addpath('matlab'); generate_vectors('build/matlab_vectors'); analyze_filter('build/matlab_analysis')"

compare-matlab:
	$(PYTHON) scripts/compare_matlab.py build/matlab_vectors

clean:
	rm -rf build model/__pycache__ scripts/__pycache__
