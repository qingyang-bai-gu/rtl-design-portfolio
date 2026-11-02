"""Integer service-cycle model for the documented serial read-then-write core.

This predicts accepted core descriptor -> accepted core result, not queue/CDC wait,
wall time, or throughput against an arbitrary slave. The fixture inserts a fixed
AR/AW/B delay and a per-beat R/W delay; those delays are explicit model inputs.
"""
from dataclasses import dataclass

from planner import config, legal, plan


@dataclass(frozen=True)
class ServiceEstimate:
    cycles: int
    read_bursts: int = 0
    read_beats: int = 0
    write_bursts: int = 0
    write_beats: int = 0
    write_responses: int = 0


def estimate(src, dst, length, *, address_width=32, data_width=128, maximum=16,
             status=0, fail_chunk=0, ar_delay=0, r_delay=0, aw_delay=0,
             w_delay=0, b_delay=0):
    config(address_width, data_width, maximum)
    delays = (ar_delay, r_delay, aw_delay, w_delay, b_delay)
    if any(delay < 0 for delay in delays) or status not in range(4):
        raise ValueError('negative delay or unsupported status')
    if status == 1:
        if legal(src, dst, length, address_width, data_width):
            raise ValueError('descriptor-error estimate requires an illegal descriptor')
        return ServiceEstimate(1)
    bursts = plan(src, dst, length, address_width, data_width, maximum)
    if status in (2, 3) and not 0 <= fail_chunk < len(bursts):
        raise ValueError('fault chunk outside descriptor')
    cycles = read_bursts = read_beats = write_bursts = write_beats = 0
    for index, (_, _, beats) in enumerate(bursts):
        read_bursts += 1
        read_beats += beats
        if status == 2 and index == fail_chunk:
            # Read issue/plan, full drain, result/flush and tagged failure completion.
            cycles += 2 * beats + 6 + ar_delay + beats * r_delay
            break
        # A successful chunk includes both engines, buffer turnaround, and control.
        cycles += (3 * beats + 9 + ar_delay + beats * r_delay
                   + aw_delay + beats * w_delay + b_delay)
        write_bursts += 1
        write_beats += beats
        if (status == 3 and index == fail_chunk) or index == len(bursts) - 1:
            cycles += 1  # Final core completion handshake, success or B failure.
            break
    return ServiceEstimate(cycles, read_bursts, read_beats, write_bursts,
                           write_beats, write_bursts)


def compare_log(output, *, address_width=32, data_width=128, maximum=16):
    """Check each quiescent measurement; reset cancels the preceding queued ledger."""
    predicted = 0
    descriptors = 0
    measurements = []
    for line in output.splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == 'MODEL_RESET':
            predicted = descriptors = 0
        elif words[0] == 'MODEL_DESC':
            src, dst, length, status, fault, ar, r, aw, w, b = map(int, words[1:])
            predicted += estimate(src, dst, length, address_width=address_width,
                                  data_width=data_width, maximum=maximum, status=status,
                                  fail_chunk=fault, ar_delay=ar, r_delay=r, aw_delay=aw,
                                  w_delay=w, b_delay=b).cycles
            descriptors += 1
        elif words[0] == 'MODEL_MEASURE':
            measured = int(words[1])
            if measured != predicted:
                raise ValueError(f'service cycles: measured {measured}, predicted {predicted}')
            measurements.append(dict(descriptors=descriptors, predicted_cycles=predicted,
                                     measured_cycles=measured, difference=measured-predicted))
    if not measurements:
        raise ValueError('simulation provided no performance measurement')
    return measurements
