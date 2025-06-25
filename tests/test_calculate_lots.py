import unittest
from unittest.mock import patch
import calculate_lots as cl
import tp_sl_calc as calc

class TestCalculateLots(unittest.TestCase):
    def setUp(self):
        # Default mock values for symbol properties
        self.account_balance = 10000.0
        self.symbol_values = {
            cl.SYMBOL_TRADE_TICK_VALUE: 1.0,
            cl.SYMBOL_TRADE_TICK_SIZE: 0.0001,
            cl.SYMBOL_VOLUME_STEP: 0.01,
            cl.SYMBOL_VOLUME_MIN: 0.01,
            cl.SYMBOL_VOLUME_MAX: 1.0,
        }

    def fake_account_info(self, prop):
        if prop == cl.ACCOUNT_BALANCE:
            return self.account_balance
        raise ValueError

    def fake_symbol_info(self, symbol, prop):
        return self.symbol_values[prop]

    @patch('calculate_lots.AccountInfoDouble')
    @patch('calculate_lots.SymbolInfoDouble')
    def test_calculate_lots_various_sl(self, mock_symbol, mock_account):
        mock_account.side_effect = self.fake_account_info
        mock_symbol.side_effect = self.fake_symbol_info

        # 50 pip stop-loss should max out at 1 lot
        self.assertEqual(cl.CalculateLots(50), 1.0)

        # 100 pip stop-loss also results in 1 lot with given risk
        self.assertEqual(cl.CalculateLots(100), 1.0)

        # Larger stop-loss reduces lot size
        self.assertEqual(cl.CalculateLots(200), 0.5)

    @patch('calculate_lots.AccountInfoDouble')
    @patch('calculate_lots.SymbolInfoDouble')
    def test_calculate_lots_dynamic_stop(self, mock_symbol, mock_account):
        mock_account.side_effect = self.fake_account_info
        mock_symbol.side_effect = self.fake_symbol_info

        entry, sl, _ = calc.calc_tp_sl(1.1000, 1.0900, entry_level=50,
                                       sl_buffer_pips=10, rr_ratio=3.0,
                                       for_sell=False, point=cl._Point)
        stop_pips = round(abs(sl - entry) / cl._Point, 2)
        self.assertEqual(cl.CalculateLots(stop_pips), 1.0)

        entry, sl, _ = calc.calc_tp_sl(1.1000, 1.0900, entry_level=50,
                                       sl_buffer_pips=150, rr_ratio=3.0,
                                       for_sell=False, point=cl._Point)
        stop_pips = round(abs(sl - entry) / cl._Point, 2)
        self.assertEqual(cl.CalculateLots(stop_pips), 0.5)

    @patch('calculate_lots.AccountInfoDouble')
    @patch('calculate_lots.SymbolInfoDouble')
    def test_calculate_lots_respects_step_precision(self, mock_symbol, mock_account):
        mock_account.side_effect = self.fake_account_info
        mock_symbol.side_effect = self.fake_symbol_info

        self.symbol_values[cl.SYMBOL_VOLUME_STEP] = 0.001
        self.symbol_values[cl.SYMBOL_VOLUME_MIN] = 0.001

        self.assertEqual(cl.CalculateLots(426.63), 0.234)

    @patch('calculate_lots.AccountInfoDouble')
    @patch('calculate_lots.SymbolInfoDouble')
    def test_calculate_lots_zero_values_fallback(self, mock_symbol, mock_account):
        mock_account.side_effect = self.fake_account_info
        mock_symbol.side_effect = self.fake_symbol_info

        self.symbol_values[cl.SYMBOL_VOLUME_STEP] = 0.0
        self.symbol_values[cl.SYMBOL_TRADE_TICK_VALUE] = 0.0

        self.assertEqual(cl.CalculateLots(50), self.symbol_values[cl.SYMBOL_VOLUME_MIN])

    @patch('calculate_lots.AccountInfoDouble')
    @patch('calculate_lots.SymbolInfoDouble')
    def test_calculate_lots_accepts_default_lot(self, mock_symbol, mock_account):
        mock_account.side_effect = self.fake_account_info
        mock_symbol.side_effect = self.fake_symbol_info

        # Smaller account size to force a default lot calculation
        self.account_balance = 100.0

        self.assertEqual(cl.CalculateLots(100), cl.DEFAULT_LOT)

    @patch('calculate_lots.AccountInfoDouble')
    @patch('calculate_lots.SymbolInfoDouble')
    def test_calculate_lots_secure_step_min_values(self, mock_symbol, mock_account):
        mock_account.side_effect = self.fake_account_info
        mock_symbol.side_effect = self.fake_symbol_info

        # Provide invalid step and minimum lot values
        self.symbol_values[cl.SYMBOL_VOLUME_STEP] = -0.05
        self.symbol_values[cl.SYMBOL_VOLUME_MIN] = -0.01

        self.account_balance = 100.0

        self.assertEqual(cl.CalculateLots(1000), cl.DEFAULT_LOT)

    @patch('calculate_lots.AccountInfoDouble')
    @patch('calculate_lots.SymbolInfoDouble')
    def test_calculate_lots_from_price(self, mock_symbol, mock_account):
        mock_account.side_effect = self.fake_account_info
        mock_symbol.side_effect = self.fake_symbol_info

        lots = cl.CalculateLotsFromPrice(
            stop_loss_price=1.0950,
            order_type=cl.ORDER_TYPE_BUY,
            ask=1.1000,
            bid=1.0995,
        )
        self.assertEqual(lots, 1.0)

        lots = cl.CalculateLotsFromPrice(
            stop_loss_price=1.1220,
            order_type=cl.ORDER_TYPE_SELL,
            ask=1.1002,
            bid=1.1000,
        )
        self.assertEqual(lots, 0.45)

if __name__ == '__main__':
    unittest.main()
