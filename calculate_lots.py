"""Utilities for computing position size.

The module exposes :func:`CalculateLots` which returns the recommended lot
size for a trade based on a stop-loss distance and the percentage of account
balance to risk. Account and symbol information is retrieved via the
``AccountInfoDouble`` and ``SymbolInfoDouble`` functions that replicate the
MetaTrader API.

Parameters
----------
sl_pips : float
    Stop-loss distance in pips provided to :func:`CalculateLots`.
risk_percent : float, optional
    Percentage of the account balance to risk, default ``1.0``.

Returns
-------
float
    Recommended lot size rounded to the symbol's volume step. If symbol data
    is not available a ``DEFAULT_LOT`` value is returned.
"""

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


ORDER_TYPE_BUY = 0
"""Constant representing a buy order."""

ORDER_TYPE_SELL = 1
"""Constant representing a sell order."""


def CalculateLotsFromPrice(
    stop_loss_price,
    order_type,
    ask,
    bid,
    risk_percent=1.0,
    buffer_pips=0.0,
):
    """Calculate position size from a stop price and current market prices.

    Parameters
    ----------
    stop_loss_price : float
        Price level of the stop loss.
    order_type : int
        ``ORDER_TYPE_BUY`` or ``ORDER_TYPE_SELL``.
    ask : float
        Current ask price of the symbol.
    bid : float
        Current bid price of the symbol.
    risk_percent : float, optional
        Percentage of the account balance to risk, default ``1.0``.
    buffer_pips : float, optional
        Additional pips added to the stop distance, default ``0.0``.

    Returns
    -------
    float
        Recommended lot size calculated from the price based stop distance.
    """

    if order_type == ORDER_TYPE_BUY:
        sl_distance_price = ask - stop_loss_price
    elif order_type == ORDER_TYPE_SELL:
        sl_distance_price = stop_loss_price - bid
    else:
        raise ValueError("invalid order type")

    sl_distance_price = abs(sl_distance_price) + buffer_pips * _Point
    sl_pips = sl_distance_price / _Point
    return CalculateLots(sl_pips, risk_percent)

