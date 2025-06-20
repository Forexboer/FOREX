import unittest
import tp_sl_calc as calc

class TestTPSLCalc(unittest.TestCase):
    def test_buy_calculation(self):
        fib_high = 1.1000
        fib_low = 1.0900
        entry, sl, tp = calc.calc_tp_sl(fib_high, fib_low, entry_level=50, sl_buffer_pips=10, rr_ratio=3.0, for_sell=False, point=0.0001)
        self.assertAlmostEqual(entry, 1.0950, places=5)
        self.assertAlmostEqual(sl, 1.0890, places=5)
        self.assertAlmostEqual(tp, 1.1130, places=5)

    def test_sell_calculation(self):
        fib_high = 1.1000
        fib_low = 1.0900
        entry, sl, tp = calc.calc_tp_sl(fib_high, fib_low, entry_level=50, sl_buffer_pips=10, rr_ratio=3.0, for_sell=True, point=0.0001)
        self.assertAlmostEqual(entry, 1.0950, places=5)
        self.assertAlmostEqual(sl, 1.1010, places=5)
        self.assertAlmostEqual(tp, 1.0770, places=5)

if __name__ == '__main__':
    unittest.main()
