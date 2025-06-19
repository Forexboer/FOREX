import unittest
from unittest.mock import patch
import calculate_lots as cl

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

if __name__ == '__main__':
    unittest.main()
