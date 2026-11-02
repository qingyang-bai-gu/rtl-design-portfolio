"""Hand-calculated anchors, faults, boundaries and comparison-parser checks."""
import unittest

from performance import compare_log, estimate


class PerformanceTests(unittest.TestCase):
    def test_single_beat(self):
        self.assertEqual(estimate(0, 0x8000, 16).cycles, 13)

    def test_maximum_chunk(self):
        self.assertEqual(estimate(0, 0x8000, 256).cycles, 58)

    def test_multiple_chunks(self):
        result = estimate(0, 0x8000, 1024)
        self.assertEqual((result.cycles, result.read_bursts, result.write_beats), (229, 4, 64))

    def test_different_page_limits(self):
        # Source 1 beat to boundary, then destination 1, then 4; three chunks.
        result = estimate(0xFF0, 0x8FE0, 96)
        self.assertEqual((result.cycles, result.read_bursts), (46, 3))

    def test_fixture_delays(self):
        result = estimate(0, 0x8000, 48, ar_delay=2, r_delay=1,
                          aw_delay=4, w_delay=2, b_delay=3)
        self.assertEqual(result.cycles, 37)

    def test_read_error_drains_and_suppresses_write(self):
        result = estimate(0, 0x8000, 272, status=2, fail_chunk=1)
        self.assertEqual((result.cycles, result.read_beats, result.write_beats), (65, 17, 16))

    def test_write_error_preserves_accepted_writes(self):
        result = estimate(0, 0x8000, 768, status=3, fail_chunk=1)
        self.assertEqual((result.cycles, result.write_bursts, result.write_beats), (115, 2, 32))

    def test_invalid_descriptor(self):
        self.assertEqual(estimate(0, 0, 16, status=1).cycles, 1)
        with self.assertRaises(ValueError):
            estimate(0, 0x8000, 16, status=1)

    def test_invalid_model_inputs(self):
        for kwargs in [dict(r_delay=-1), dict(status=4), dict(status=2, fail_chunk=2),
                       dict(data_width=24), dict(maximum=0)]:
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                estimate(0, 0x8000, 16, **kwargs)

    def test_log_reset_and_measurement(self):
        log = ('MODEL_RESET\nMODEL_DESC 0 32768 16 0 0 0 0 0 0 0\n'
               'MODEL_MEASURE 13\nMODEL_DESC 0 32768 256 0 0 0 0 0 0 0\n'
               'MODEL_RESET\nMODEL_DESC 0 0 16 1 0 0 0 0 0 0\nMODEL_MEASURE 1\n')
        measurements = compare_log(log)
        self.assertEqual([row['measured_cycles'] for row in measurements], [13, 1])
        self.assertTrue(all(row['difference'] == 0 for row in measurements))

    def test_log_rejects_mismatch_and_missing_measurement(self):
        for log in ['MODEL_MEASURE 1', 'MODEL_RESET',
                    'MODEL_DESC 0 32768 16 0 0 0 0 0 0 0\nMODEL_MEASURE 12']:
            with self.subTest(log=log), self.assertRaises(ValueError):
                compare_log(log)


if __name__ == '__main__':
    unittest.main()
