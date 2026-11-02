# Toolchain

Behavioral regression: Python 3.10.7 and Icarus Verilog/vvp 13.0 (v13_0).
Formatting/style: pinned Verible v0.0-3860-gf3da2ce6 (Intel macOS official release).
Independent static lint: Verilator 5.046, official Homebrew Intel binary package.
No third-party Python packages are required for the RTL regression or quality gates.

`make clean check` records exact tool versions, per-run outcomes, and source hashes
under build/. Reviewed copies are retained in docs/verification_results.json,
docs/style_results.json, and docs/lint_results.json. Detailed run logs are
ignored by Git. See CODING_STANDARD.md for formatter installation and lint waivers.

Verible is cached in `.tools/verible/bin`. The current Intel Verilator package is
cached in `.tools/verilator/5.046`; `quality.py` uses its matching support directory.
Alternatively install Verilator on PATH, or set VERILATOR to an executable path.
Only named open outputs, ordinary verification blocking assignments/declaration
initialization, and specific testbench reset nets that deliberately feed synchronous
and asynchronous consumers have lint waivers. See config/verilator.vlt and CDC.md.

Behavioral multi-channel/CDC and measured service-cycle evidence is documented in
VERIFICATION.md. No formal, synthesis, physical CDC, timing, area or power signoff is
claimed. Static lint is independent frontend checking, not a hardware signoff.
