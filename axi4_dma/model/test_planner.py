import random
import unittest
from planner import config, legal, plan


class PlannerTests(unittest.TestCase):
    def test_one(self):
        self.assertEqual(plan(0, 8192, 16), [(0, 8192, 1)])

    def test_maximum(self):
        self.assertEqual(plan(0, 8192, 256)[0][2], 16)

    def test_split(self):
        self.assertEqual([x[2] for x in plan(0, 8192, 1024)], [16] * 4)

    def test_source_boundary(self):
        self.assertEqual(plan(4080, 8192, 64)[0][2], 1)

    def test_destination_boundary(self):
        self.assertEqual(plan(0, 12256, 64)[0][2], 2)

    def test_both(self):
        self.assertEqual(plan(4080, 12256, 64)[0][2], 1)

    def test_endpoint(self):
        self.assertTrue(legal(0, 2**64 - 16, 16, 64))
        self.assertFalse(legal(0, 2**64 - 16, 32, 64))

    def test_alignment(self):
        for args in [(1, 8192, 16), (0, 8193, 16), (0, 8192, 17)]:
            self.assertFalse(legal(*args))

    def test_range(self):
        for args in [(0, 8192, 0), (-16, 8192, 16), (0, 16, 32)]:
            self.assertFalse(legal(*args))

    def test_parameters(self):
        for aw, dw, mb in [(11, 128, 16), (65, 128, 16), (32, 0, 16),
                           (32, 24, 16), (32, 2048, 16), (32, 128, 0),
                           (32, 128, 257)]:
            with self.assertRaises(ValueError):
                config(aw, dw, mb)

    def test_extremes(self):
        self.assertEqual(plan(0, 2048, 256, 12, 8, 256)[0][2], 256)
        self.assertEqual(plan(0, 8192, 4096, 64, 1024, 256)[0][2], 32)
        self.assertEqual(len(plan(0, 8192, 4, 32, 8, 1)), 4)

    def test_conservation(self):
        rng = random.Random(1941)
        for _ in range(300):
            src, dst = rng.randrange(256) * 16, 8192 + rng.randrange(256) * 16
            length = rng.randrange(1, 200) * 16
            chunks = plan(src, dst, length)
            self.assertEqual(sum(n * 16 for _, _, n in chunks), length)
            for s, d, n in chunks:
                self.assertEqual((s - src), (d - dst))
                self.assertTrue(1 <= n <= 16)
                self.assertEqual(s // 4096, (s + n * 16 - 1) // 4096)
                self.assertEqual(d // 4096, (d + n * 16 - 1) // 4096)
                src, dst = s + n * 16, d + n * 16
