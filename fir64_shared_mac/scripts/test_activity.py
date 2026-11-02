import tempfile
from pathlib import Path
import unittest
from activity import analyze


class ActivityTests(unittest.TestCase):
    def test_case_sensitive_ids_aliases_and_unknowns(self):
        # VCD identifiers A and a refer to distinct signals, including vectors.
        fixture = """$timescale
1ns
$end
$scope module dut $end
$var wire 2 A upper [1:0] $end
$var wire 2 a lower [1:0] $end
$var wire 2 A upper_alias [1:0] $end
$var wire 1 B scalar $end
$upscope $end
$enddefinitions $end
#0
b00 A
b11 a
xB
#5
b11 A
b10 a
0B
#10
b1 A
bx a
1B
#15
b0 a
zB
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.vcd"
            path.write_text(fixture)
            result = analyze(path)
        self.assertEqual(result["known_bit_transitions"], 5)
        self.assertEqual(result["unique_signal_ids"], 3)
        self.assertEqual(result["duration_ticks"], 15)
        self.assertEqual(result["vcd_timescale"], "1ns")
        self.assertEqual(result["top_signals"][0]["names"], ["dut.upper", "dut.upper_alias"])
        self.assertEqual(result["top_signals"][0]["bit_transitions"], 3)


if __name__ == "__main__":
    unittest.main()
