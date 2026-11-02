"""Build and run self-checking simulations. Run from the project root via Make."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
BUILD = ROOT / 'build'
BUILD.mkdir(exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument('--stage', default='all', choices=[
    'all', 'planner', 'read', 'write', 'buffer', 'controller', 'memory', 'system',
    'parameters', 'shell', 'monitor', 'arbiter', 'multi', 'cdc', 'cdc_units', 'counters',
    'extension_parameters'])
args = parser.parse_args()
results = []
performance_results = []
sys.path.insert(0, str(ROOT / 'model'))
from performance import compare_log  # Project-local independent integer model.


def run(name, command, expected_failure=False, marker='PARAM:'):
    start = time.monotonic()
    proc = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=120)
    (BUILD / f'{name}.log').write_text(proc.stdout)
    passed = (proc.returncode != 0 and marker in proc.stdout if expected_failure
              else proc.returncode == 0)
    results.append(dict(name=name, passed=passed, expected_failure=expected_failure,
                        seconds=round(time.monotonic()-start, 3)))
    if not passed:
        print(proc.stdout)
        raise RuntimeError(f'{name} failed; see build/{name}.log')
    print(f'PASS {name}' + (' (expected rejection)' if expected_failure else ''), flush=True)
    return proc.stdout


def sim(name, top, sources, parameters=None, expected_failure=False, marker='PARAM:'):
    image = str(BUILD / f'{name}.vvp')
    command = ['iverilog', '-g2012', '-Wall', '-Irtl', '-s', top, '-o', image]
    command += [f'-P{top}.{k}={v}' for k, v in (parameters or {}).items()]
    command += sources
    compile_output = run(name + '_compile', command)
    if not expected_failure and any(word in compile_output.lower()
                                    for word in ['warning:', 'sorry:', 'error:']):
        raise RuntimeError(f'{name} emitted a compiler diagnostic; review its compile log')
    output = run(name, ['vvp', image], expected_failure, marker)
    if not expected_failure and 'PASS' not in output:
        raise RuntimeError(f'{name} terminated without PASS')
    if top == 'tb_multi' and not expected_failure:
        params = parameters or {}
        measurements = compare_log(output, address_width=params.get('ADDR_WIDTH', 32),
                                   data_width=params.get('DATA_WIDTH', 128),
                                   maximum=params.get('MAX_BURST_BEATS', 16))
        performance_results.append(dict(name=name, parameters=params, measurements=measurements))
    return output


try:
    if args.stage in ('all', 'planner'):
        run('reference', [sys.executable, '-m', 'unittest', 'discover', '-s', 'model', '-v'])
        run('vectors', [sys.executable, 'model/planner.py', '--output',
                        'build/planner_vectors.txt'])
        for aw, dw, mb in [(32, 128, 16), (12, 8, 1), (64, 1024, 256),
                           (64, 8, 256), (12, 1024, 3)]:
            sim(f'planner_{aw}_{dw}_{mb}', 'tb_planner',
                ['rtl/dma_burst_planner.sv', 'tb/tb_planner.sv'],
                dict(ADDR_WIDTH=aw, DATA_WIDTH=dw, MAX_BURST_BEATS=mb))
    if args.stage in ('all', 'read'):
        for aw, dw, mb in [(32, 128, 16), (12, 8, 1), (64, 1024, 256), (64, 8, 256)]:
            sim(f'read_{aw}_{dw}_{mb}', 'tb_read',
                ['rtl/dma_read_engine.sv', 'tb/rv_stability.sv', 'tb/tb_read.sv'],
                dict(ADDR_WIDTH=aw, DATA_WIDTH=dw, MAX_BURST_BEATS=mb))
    if args.stage in ('all', 'write'):
        for aw, dw, mb in [(32, 128, 16), (12, 8, 1), (64, 1024, 256), (64, 8, 256)]:
            sim(f'write_{aw}_{dw}_{mb}', 'tb_write',
                ['rtl/dma_write_engine.sv', 'tb/rv_stability.sv', 'tb/tb_write.sv'],
                dict(ADDR_WIDTH=aw, DATA_WIDTH=dw, MAX_BURST_BEATS=mb))
    if args.stage in ('all', 'buffer'):
        for depth, width in [(1, 128), (3, 128), (4, 128), (5, 128), (16, 128),
                             (1, 1), (5, 1024)]:
            sim(f'buffer_{depth}_{width}', 'tb_buffer',
                ['rtl/dma_burst_buffer.sv', 'tb/rv_stability.sv', 'tb/tb_buffer.sv'],
                dict(DEPTH=depth, DATA_WIDTH=width))
        for name, params in [('zero_depth', dict(DEPTH=0)),
                             ('zero_width', dict(DATA_WIDTH=0))]:
            sim(f'buffer_reject_{name}', 'tb_parameters',
                ['rtl/dma_burst_buffer.sv', 'tb/tb_parameters.sv'],
                dict(KIND=3, **params), expected_failure=True)
    if args.stage in ('all', 'controller'):
        for aw, dw, mb, tw in [(32, 128, 16, 8), (12, 8, 1, 1), (64, 1024, 256, 8)]:
            sim(f'controller_{aw}_{dw}_{mb}', 'tb_controller',
                ['rtl/dma_controller.sv', 'tb/rv_stability.sv', 'tb/tb_controller.sv'],
                dict(ADDR_WIDTH=aw, DATA_WIDTH=dw, MAX_BURST_BEATS=mb, TAG_WIDTH=tw))
    if args.stage in ('all', 'memory'):
        for dw in [8, 128, 1024]:
            sim(f'memory_{dw}', 'tb_memory',
                ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_memory.sv'],
                dict(DATA_WIDTH=dw))
    if args.stage in ('all', 'system'):
        for aw, dw, mb in [(32, 128, 16), (12, 8, 1), (64, 1024, 256), (32, 128, 3)]:
            sim(f'system_{aw}_{dw}_{mb}', 'tb_system',
                sorted(str(x) for x in Path('rtl').glob('*.sv')) +
                ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_system.sv'],
                dict(ADDR_WIDTH=aw, DATA_WIDTH=dw, MAX_BURST_BEATS=mb))
    if args.stage in ('all', 'parameters'):
        sources = sorted(str(x) for x in Path('rtl').glob('*.sv')) + ['tb/tb_parameters.sv']
        invalid_geometry = [dict(ADDR_WIDTH=11), dict(ADDR_WIDTH=65),
                            dict(DATA_WIDTH=0), dict(DATA_WIDTH=7), dict(DATA_WIDTH=24),
                            dict(DATA_WIDTH=2048), dict(MAX_BURST_BEATS=0),
                            dict(MAX_BURST_BEATS=257)]
        for kind in [0, 1, 2, 4, 5]:
            for index, params in enumerate(invalid_geometry):
                sim(f'parameter_reject_{kind}_{index}', 'tb_parameters', sources,
                    dict(KIND=kind, **params), expected_failure=True)
        for kind, params in [(1, dict(ID_WIDTH=0)), (2, dict(ID_WIDTH=0)),
                             (4, dict(TAG_WIDTH=0)), (5, dict(ID_WIDTH=0)),
                             (5, dict(TAG_WIDTH=0)), (5, dict(DEPTH=15)),
                             (5, dict(DEPTH=0))]:
            suffix = '_'.join(f'{k}_{v}' for k, v in params.items())
            sim(f'parameter_reject_{kind}_{suffix}', 'tb_parameters', sources,
                dict(KIND=kind, **params), expected_failure=True)
    if args.stage in ('all', 'parameters'):
        memory_sources = ['tb/axi_memory_model.sv', 'tb/tb_parameters.sv']
        for index, params in enumerate([
                dict(ADDR_WIDTH=11), dict(ADDR_WIDTH=65), dict(DATA_WIDTH=0),
                dict(DATA_WIDTH=7), dict(DATA_WIDTH=24), dict(DATA_WIDTH=2048),
                dict(ID_WIDTH=0), dict(MEM_BYTES=0)]):
            sim(f'memory_parameter_reject_{index}', 'tb_parameters', memory_sources,
                dict(KIND=6, **params), expected_failure=True)
    if args.stage in ('all', 'shell'):
        for count in [1, 3, 4, 5]:
            sim(f'arbiter_elaboration_{count}', 'tb_arbiter_elaboration',
                ['rtl/round_robin_arbiter.sv', 'tb/tb_arbiter_elaboration.sv'],
                dict(REQUESTERS=count))
        sim('arbiter_elaboration_reject_zero', 'tb_arbiter_elaboration',
            ['rtl/round_robin_arbiter.sv', 'tb/tb_arbiter_elaboration.sv'],
            dict(REQUESTERS=0), expected_failure=True)
    if args.stage in ('all', 'monitor'):
        for mode in range(7):
            sim(f'rv_monitor_{mode}', 'tb_rv_stability',
                ['tb/rv_stability.sv', 'tb/tb_rv_stability.sv'],
                dict(MODE=mode), expected_failure=mode != 0, marker='RV:')
    if args.stage in ('all', 'arbiter'):
        for count in [1, 3, 4, 5, 8]:
            sim(f'arbiter_{count}', 'tb_arbiter',
                ['rtl/round_robin_arbiter.sv', 'tb/rv_stability.sv', 'tb/tb_arbiter.sv'],
                dict(REQUESTERS=count))
        sim('arbiter_withdrawal', 'tb_arbiter',
            ['rtl/round_robin_arbiter.sv', 'tb/rv_stability.sv', 'tb/tb_arbiter.sv'],
            dict(REQUESTERS=3, WITHDRAW=1), expected_failure=True, marker='CONTRACT:')
    if args.stage in ('all', 'multi'):
        for channels, aw, dw, maximum in [(4, 32, 128, 16), (3, 32, 128, 3),
                                           (1, 12, 8, 1), (5, 64, 1024, 256)]:
            sim(f'multi_{channels}_{aw}_{dw}_{maximum}', 'tb_multi',
                sorted(str(x) for x in Path('rtl').glob('*.sv')) +
                ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_multi.sv'],
                dict(CHANNELS=channels, ADDR_WIDTH=aw, DATA_WIDTH=dw,
                     MAX_BURST_BEATS=maximum))
        sim('multi_queue_depths', 'tb_multi',
            sorted(str(x) for x in Path('rtl').glob('*.sv')) +
            ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_multi.sv'],
            dict(CHANNELS=3, DESCRIPTOR_DEPTH=3, COMPLETION_DEPTH=3))
        for name, params in [('multi_zero_delay', dict(AR_DELAY=0, R_DELAY=0, AW_DELAY=0,
                                                        W_DELAY=0, B_DELAY=0)),
                             ('multi_delays', dict(AR_DELAY=1, R_DELAY=3, AW_DELAY=4,
                                                  W_DELAY=1, B_DELAY=2))]:
            sim(name, 'tb_multi', sorted(str(x) for x in Path('rtl').glob('*.sv')) +
                ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_multi.sv'], params)
    if args.stage in ('all', 'cdc'):
        for channels, depth, control, axi, phase in [(4, 4, 3, 5, 1), (3, 2, 7, 2, 3),
                                                     (1, 8, 2, 7, 4)]:
            sim(f'cdc_{channels}_{depth}_{control}_{axi}_{phase}', 'tb_multi',
                sorted(str(x) for x in Path('rtl').glob('*.sv')) +
                ['tb/axi_memory_model.sv', 'tb/rv_stability.sv', 'tb/tb_multi.sv'],
                dict(CHANNELS=channels, CDC_DEPTH=depth, CTRL_HALF=control,
                     AXI_HALF=axi, AXI_PHASE=phase, CDC_ENABLE=1))
    if args.stage in ('all', 'counters'):
        for width in [1, 4, 32, 64]:
            sim(f'counters_{width}', 'tb_counters',
                ['rtl/dma_performance_counters.sv', 'tb/tb_counters.sv'],
                dict(COUNTER_WIDTH=width))
    if args.stage in ('all', 'cdc_units'):
        for stages in [2, 3, 4]:
            sim(f'synchronizers_{stages}', 'tb_synchronizers',
                ['rtl/reset_sync.sv', 'rtl/cdc_bit_sync.sv', 'tb/tb_synchronizers.sv'],
                dict(STAGES=stages))
        for width, depth, wh, rh, phase in [(1, 2, 3, 5, 1), (128, 4, 2, 7, 3),
                                            (1024, 8, 7, 2, 0), (17, 16, 3, 3, 0)]:
            sim(f'async_fifo_{width}_{depth}_{wh}_{rh}_{phase}', 'tb_async_fifo',
                ['rtl/reset_sync.sv', 'rtl/cdc_bit_sync.sv', 'rtl/dma_async_fifo.sv',
                 'tb/rv_stability.sv', 'tb/tb_async_fifo.sv'],
                dict(DATA_WIDTH=width, DEPTH=depth, WR_HALF=wh, RD_HALF=rh, RD_PHASE=phase))
    if args.stage in ('all', 'extension_parameters'):
        cases = [(0, dict(STAGES=0)), (0, dict(STAGES=1)), (1, dict(STAGES=1)),
                 (1, dict(DATA_WIDTH=0)), (2, dict(DATA_WIDTH=0)), (2, dict(DEPTH=0)),
                 (2, dict(DEPTH=1)), (2, dict(DEPTH=3)), (3, dict(COUNTER_WIDTH=0)),
                 (4, dict(CHANNELS=0)), (4, dict(DESCRIPTOR_DEPTH=0)),
                 (4, dict(COMPLETION_DEPTH=0)), (4, dict(COUNTER_WIDTH=0)),
                 (4, dict(TAG_WIDTH=0)), (4, dict(ID_WIDTH=0)),
                 (5, dict(DEPTH=3)), (5, dict(DEPTH=1)), (5, dict(CHANNELS=0)),
                 (5, dict(COUNTER_WIDTH=0)), (6, dict(CHANNELS=0)),
                 (6, dict(INDEX_WIDTH=0)), (6, dict(CHANNELS=5, INDEX_WIDTH=2))]
        for index, (kind, params) in enumerate(cases):
            sim(f'extension_reject_{index}', 'tb_extension_parameters',
                sorted(str(x) for x in Path('rtl').glob('*.sv')) +
                ['tb/tb_extension_parameters.sv'], dict(KIND=kind, **params),
                expected_failure=True)
finally:
    (BUILD / 'performance_results.json').write_text(json.dumps(dict(
        passed=sys.exc_info()[0] is None,
        scope='core service cycles; excludes scheduler, queue and CDC wait',
        model_sha256=hashlib.sha256((ROOT / 'model/performance.py').read_bytes()).hexdigest(),
        configurations=performance_results), indent=2) + '\n')
    versions = {}
    for tool, command in [('python', [sys.executable, '--version']),
                          ('iverilog', ['iverilog', '-V']), ('vvp', ['vvp', '-V'])]:
        try:
            out = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT).stdout
            versions[tool] = out.splitlines()[0]
        except FileNotFoundError:
            versions[tool] = 'missing'
    (BUILD / 'results.json').write_text(json.dumps(
        dict(versions=versions, stage=args.stage,
             passed=sys.exc_info()[0] is None and all(r['passed'] for r in results),
             source_sha256={str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                            for directory in ['rtl', 'tb', 'model', 'scripts']
                            for path in sorted(Path(directory).glob('*')) if path.is_file()},
             results=results), indent=2) + '\n')
