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

# Default lot size returned when the symbol data is not usable
DEFAULT_LOT = 0.01

# These functions will be mocked in tests

def AccountInfoDouble(property_id):
    raise NotImplementedError

def SymbolInfoDouble(symbol, property_id):
    raise NotImplementedError


def _count_decimals(step):
    """Return the number of decimal places required to represent the step."""
    step_str = f"{step:.10f}".rstrip("0")
    if "." in step_str:
        return len(step_str.split(".")[1])
    return 0


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

    # Validate step and minimum lot values to avoid invalid calculations
    if step <= 0:
        step = min_lot if min_lot > 0 else DEFAULT_LOT
    if min_lot <= 0:
        min_lot = DEFAULT_LOT
    if max_lot < min_lot:
        max_lot = min_lot

    lots = math.floor(raw_lots / step) * step
    decimals = _count_decimals(step)
    lots = round(lots, decimals)

    if lots < min_lot:
        return min_lot
    if lots > max_lot:
        return max_lot
    return lots
