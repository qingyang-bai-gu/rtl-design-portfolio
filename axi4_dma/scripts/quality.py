"""Reproducible HDL formatting, style, and independent lint gates; see CODING_STANDARD.md."""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
SOURCES = sorted([*Path('rtl').glob('*.sv'), *Path('rtl').glob('*.svh'),
                  *Path('tb').glob('*.sv')])
RTL = sorted(str(path) for path in Path('rtl').glob('*.sv'))
GEOMETRIES = [(32, 128, 16), (12, 8, 1), (64, 1024, 256)]


def tool(name):
    if name == 'verilator':
        override = os.environ.get('VERILATOR')
        candidate = Path(override) if override else ROOT / '.tools/verilator/5.046/bin/verilator'
        if candidate.is_file():
            return str(candidate)
    if name.startswith('verible-'):
        directory = os.environ.get('VERIBLE_BIN', str(ROOT / '.tools/verible/bin'))
        candidate = Path(directory) / name
        if candidate.is_file():
            return str(candidate)
    executable = shutil.which(name)
    if executable:
        return executable
    raise RuntimeError(f'{name} missing; see docs/CODING_STANDARD.md for installation')


def invoke(command):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout or f'command failed: {command}')
    return result.stdout


def source_hashes():
    paths = SOURCES + sorted(Path('config').glob('*')) + [Path('scripts/quality.py')]
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def format_and_style(write=False):
    formatter = tool('verible-verilog-format')
    linter = tool('verible-verilog-lint')
    problems = []
    for path in SOURCES:
        original = path.read_text()
        formatted = invoke([formatter, '--flagfile=config/verible-format.flags', str(path)])
        if write:
            path.write_text(formatted)
        elif original != formatted:
            problems.append(''.join(difflib.unified_diff(
                original.splitlines(True), formatted.splitlines(True),
                fromfile=str(path), tofile=f'{path} (formatted)')))
        text = formatted if write else original
        for number, line in enumerate(text.splitlines(), 1):
            if '\t' in line or line.rstrip() != line or len(line) > 100:
                problems.append(f'{path}:{number}: tab, trailing space, or >100 columns')
        if not text.endswith('\n'):
            problems.append(f'{path}: missing final newline')
    if problems:
        raise RuntimeError('\n'.join(problems))
    invoke([linter, '--rules_config=config/verible.rules', *map(str, SOURCES)])
    print(f'PASS formatting and Verible style: {len(SOURCES)} HDL files', flush=True)
    Path('build').mkdir(exist_ok=True)
    Path('build/style_results.json').write_text(json.dumps(dict(
        passed=True, version=invoke([formatter, '--version']).splitlines()[0],
        source_sha256=source_hashes()), indent=2) + '\n')


def lint():
    executable = tool('verilator')
    environment = os.environ.copy()
    support = Path(executable).resolve().parent.parent / 'share/verilator'
    if support.is_dir():
        environment.setdefault('VERILATOR_ROOT', str(support))
    jobs = []
    for aw, dw, maximum in GEOMETRIES + [(32, 128, 3)]:
        params = dict(ADDR_WIDTH=aw, DATA_WIDTH=dw, MAX_BURST_BEATS=maximum)
        jobs.append((f'rtl_{aw}_{dw}_{maximum}', 'axi_dma', RTL, params))
    for top, module in [('tb_read', 'dma_read_engine'), ('tb_write', 'dma_write_engine'),
                        ('tb_controller', 'dma_controller')]:
        geometries = GEOMETRIES if top == 'tb_controller' else GEOMETRIES + [(64, 8, 256)]
        for aw, dw, maximum in geometries:
            jobs.append((f'{top}_{aw}_{dw}_{maximum}', top,
                         [f'rtl/{module}.sv', 'tb/rv_stability.sv', f'tb/{top}.sv'],
                         dict(ADDR_WIDTH=aw, DATA_WIDTH=dw, MAX_BURST_BEATS=maximum)))
    for aw, dw, maximum in GEOMETRIES + [(64, 8, 256), (12, 1024, 3)]:
        jobs.append((f'planner_{aw}_{dw}_{maximum}', 'tb_planner',
                     ['rtl/dma_burst_planner.sv', 'tb/tb_planner.sv'],
                     dict(ADDR_WIDTH=aw, DATA_WIDTH=dw, MAX_BURST_BEATS=maximum)))
    for depth, width in [(1, 128), (3, 128), (4, 128), (5, 128), (16, 128),
                         (1, 1), (5, 1024)]:
        jobs.append((f'buffer_{depth}_{width}', 'tb_buffer',
                     ['rtl/dma_burst_buffer.sv', 'tb/rv_stability.sv', 'tb/tb_buffer.sv'],
                     dict(DEPTH=depth, DATA_WIDTH=width)))
    for width in [8, 128, 1024]:
        jobs.append((f'memory_{width}', 'tb_memory',
                     ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_memory.sv'],
                     dict(DATA_WIDTH=width)))
    for aw, dw, maximum in GEOMETRIES + [(32, 128, 3)]:
        jobs.append((f'system_{aw}_{dw}_{maximum}', 'tb_system',
                     RTL + ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_system.sv'],
                     dict(ADDR_WIDTH=aw, DATA_WIDTH=dw, MAX_BURST_BEATS=maximum)))
    for count in [1, 3, 4, 5]:
        jobs.append((f'shell_{count}', 'tb_arbiter_elaboration',
                     ['rtl/round_robin_arbiter.sv', 'tb/tb_arbiter_elaboration.sv'],
                     dict(REQUESTERS=count)))
    for kind in range(7):
        jobs.append((f'parameter_harness_{kind}', 'tb_parameters',
                     RTL + ['tb/axi_memory_model.sv', 'tb/tb_parameters.sv'], dict(KIND=kind)))
    jobs.append(('rv_monitor', 'tb_rv_stability',
                 ['tb/rv_stability.sv', 'tb/tb_rv_stability.sv'], {}))
    for count in [1, 3, 4, 5, 8]:
        jobs.append((f'arbiter_{count}', 'tb_arbiter',
                     ['rtl/round_robin_arbiter.sv', 'tb/rv_stability.sv', 'tb/tb_arbiter.sv'],
                     dict(REQUESTERS=count)))
    for channels, aw, dw, maximum in [(4, 32, 128, 16), (3, 32, 128, 3),
                                       (1, 12, 8, 1), (5, 64, 1024, 256)]:
        params = dict(CHANNELS=channels, ADDR_WIDTH=aw, DATA_WIDTH=dw,
                      MAX_BURST_BEATS=maximum)
        jobs.append((f'multi_{channels}_{aw}_{dw}_{maximum}', 'tb_multi',
                     RTL + ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_multi.sv'],
                     params))
    jobs.append(('multi_queue_depths', 'tb_multi',
                 RTL + ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_multi.sv'],
                 dict(CHANNELS=3, DESCRIPTOR_DEPTH=3, COMPLETION_DEPTH=3)))
    for name, params in [('multi_zero_delay', dict(AR_DELAY=0, R_DELAY=0, AW_DELAY=0,
                                                    W_DELAY=0, B_DELAY=0)),
                         ('multi_delays', dict(AR_DELAY=1, R_DELAY=3, AW_DELAY=4,
                                              W_DELAY=1, B_DELAY=2))]:
        jobs.append((name, 'tb_multi',
                     RTL + ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_multi.sv'],
                     params))
    for channels, depth, control, axi, phase in [(4, 4, 3, 5, 1), (3, 2, 7, 2, 3),
                                                 (1, 8, 2, 7, 4)]:
        jobs.append((f'cdc_{channels}_{depth}_{control}_{axi}_{phase}', 'tb_multi',
                     RTL + ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_multi.sv'],
                     dict(CHANNELS=channels, CDC_DEPTH=depth, CTRL_HALF=control,
                          AXI_HALF=axi, AXI_PHASE=phase, CDC_ENABLE=1)))
    for width in [1, 4, 32, 64]:
        jobs.append((f'counters_{width}', 'tb_counters',
                     ['rtl/dma_performance_counters.sv', 'tb/tb_counters.sv'],
                     dict(COUNTER_WIDTH=width)))
    for stages in [2, 3, 4]:
        jobs.append((f'synchronizers_{stages}', 'tb_synchronizers',
                     ['rtl/reset_sync.sv', 'rtl/cdc_bit_sync.sv', 'tb/tb_synchronizers.sv'],
                     dict(STAGES=stages)))
    for width, depth, wh, rh, phase in [(1, 2, 3, 5, 1), (128, 4, 2, 7, 3),
                                        (1024, 8, 7, 2, 0), (17, 16, 3, 3, 0)]:
        jobs.append((f'async_fifo_{width}_{depth}', 'tb_async_fifo',
                     ['rtl/reset_sync.sv', 'rtl/cdc_bit_sync.sv', 'rtl/dma_async_fifo.sv',
                      'tb/rv_stability.sv', 'tb/tb_async_fifo.sv'],
                     dict(DATA_WIDTH=width, DEPTH=depth, WR_HALF=wh, RD_HALF=rh,
                          RD_PHASE=phase)))
    for kind in range(7):
        jobs.append((f'extension_harness_{kind}', 'tb_extension_parameters',
                     RTL + ['tb/tb_extension_parameters.sv'], dict(KIND=kind)))
    output = Path('build/lint')
    output.mkdir(parents=True, exist_ok=True)
    results = []
    for name, top, sources, parameters in jobs:
        command = [executable, '--lint-only', '--timing', '-Wall', '-Irtl',
                   '--top-module', top, '--Mdir', str(output / 'obj'),
                   'config/verilator.vlt']
        command += [f'-G{key}={value}' for key, value in parameters.items()]
        command += sources
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=120, env=environment)
        (output / f'{name}.log').write_text(result.stdout)
        results.append(dict(name=name, passed=result.returncode == 0))
        if result.returncode:
            print(result.stdout, flush=True)
    passed = all(result['passed'] for result in results)
    (output / 'results.json').write_text(json.dumps(dict(
        passed=passed, version=invoke([executable, '--version']).strip(),
        source_sha256=source_hashes(), results=results), indent=2) + '\n')
    if not passed:
        raise RuntimeError('Verilator lint failed; see build/lint/*.log')
    print(f'PASS Verilator lint: {len(jobs)} configurations', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['format', 'style', 'lint'])
    args = parser.parse_args()
    if args.action == 'lint':
        lint()
    else:
        format_and_style(write=args.action == 'format')


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
