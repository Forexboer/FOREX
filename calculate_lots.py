import math

# Constants mirroring MQL5 enums
ACCOUNT_BALANCE = 0
SYMBOL_TRADE_TICK_VALUE = 1
SYMBOL_TRADE_TICK_SIZE = 2
SYMBOL_VOLUME_STEP = 3
SYMBOL_VOLUME_MIN = 4
SYMBOL_VOLUME_MAX = 5

# Default symbol and point size used in tests
_Symbol = "EURUSD"
_Point = 0.0001

# These functions will be mocked in tests

def AccountInfoDouble(property_id):
    raise NotImplementedError

def SymbolInfoDouble(symbol, property_id):
    raise NotImplementedError


def CalculateLots(sl_pips, risk_percent=1.0):
    """Calculate position size given a stop distance in pips."""
    acc_bal = AccountInfoDouble(ACCOUNT_BALANCE)
    risk = acc_bal * risk_percent / 100.0

    tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)
    tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE)

    if tick_val <= 0 or tick_size <= 0:
        return 0.01

    sl_price = sl_pips * _Point
    per_lot_loss = (sl_price / tick_size) * tick_val
    if per_lot_loss <= 0.0:
        return 0.01

    raw_lots = risk / per_lot_loss
    step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)
    min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)
    max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)

    lots = math.floor(raw_lots / step) * step
    lots = round(lots, 2)

    if lots < min_lot:
        return min_lot
    if lots > max_lot:
        return max_lot
    return lots
