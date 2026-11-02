import unittest
from reference import coefficients, fir, quantize, stimulus


class FixedPointTests(unittest.TestCase):
    def test_rounding_boundaries(self):
        for raw, expected in [(0, 0), (16383, 0), (16384, 1), (16385, 1),
                              (-16383, 0), (-16384, -1), (-16385, -1),
                              (49152, 2), (-49152, -2),
                              ((1 << 37)-1, 32767), (-(1 << 37), -32768)]:
            with self.subTest(raw=raw):
                self.assertEqual(quantize(raw), expected)

    def test_impulse_and_order(self):
        coeffs = list(range(-32, 32))
        raw, _ = fir([32767] + [0] * 64, coeffs)
        self.assertEqual(raw, [32767 * c for c in coeffs] + [0])

    def test_full_scale_accumulator(self):
        raw, output = fir([-32768] * 65, [-32768] * 64)
        self.assertEqual(raw[63:], [1 << 36, 1 << 36])
        self.assertEqual(output[63:], [32767, 32767])
        raw, output = fir([32767] * 64, [-32768] * 64)
        self.assertEqual(raw[-1], -64 * 32767 * 32768)
        self.assertEqual(output[-1], -32768)

    def test_filter_properties(self):
        coeffs = coefficients()
        self.assertEqual(coeffs, coeffs[::-1])
        self.assertEqual(sum(coeffs), 32768)
        raw, output = fir([1000] * 65, coeffs)
        self.assertEqual(raw[-1], 1000 * 32768)
        self.assertEqual(output[-1], 1000)
        self.assertEqual(stimulus(), stimulus())


if __name__ == "__main__":
    unittest.main()
