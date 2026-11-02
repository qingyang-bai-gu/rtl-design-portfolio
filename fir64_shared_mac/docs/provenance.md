# Implementation provenance

This project implements the supplied 64-tap FIR design description. No
third-party FIR, FIFO, or MAC implementation files were downloaded, pasted, or
imported during its creation. No original 2023 source files were supplied.

The RTL, testbenches, reference-model programs, and flow scripts were written
locally for this reconstruction. The coefficient and vector hex files were
computed by `model/reference.py`; their hashes and generation parameters are in
`vectors/manifest.json`. The MATLAB generator is a separately expressed model of
the same specified arithmetic and stimulus sequence. Its execution remains
unverified because the available MATLAB license has expired.

## Standard techniques and project choices

The implementation uses established engineering techniques: direct FIR
convolution, circular sample storage, signed fixed-point arithmetic, a Hamming
windowed-sinc coefficient design, xorshift32 random stimulus, Gray-coded FIFO
pointers, two-stage synchronizers, and synchronous memory inference. These
algorithms and short HDL idioms are not unique to this project. Similar equations,
reset blocks, or memory templates in other sources do not by themselves establish
that an implementation was copied.

The concrete choices made here are documented in [architecture.md](architecture.md):
the 64-tap SRAM schedule, aligned synchronous coefficient reads, startup history
masking, 38-bit accumulator, ties-away-from-zero output quantization, output
holding behavior, and the 66-cycle sample interval. The test corpus and reset and
backpressure checks are described in [verification.md](verification.md).

Official Yosys and OpenSTA documentation was consulted for command interfaces
and tool-flow syntax. Those references are linked in [ppa.md](ppa.md). Using these
tools does not vendor their source into this project. No external HDL library,
vendor IP implementation, or standard-cell model is bundled.

## Review limits

The review covered the local implementation and limited public phrase searches.
The search results did not establish a source match, but they do not provide a
comprehensive comparison against publications or public and private repositories.
No plagiarism-scanner certification is claimed. The recorded test results
support functional behavior.
