import math


def calc_tp_sl(
    fib_high,
    fib_low,
    entry_level=50.0,
    sl_buffer_pips=10,
    rr_ratio=3.0,
    for_sell=False,
    point=0.0001,
):
    """Return entry, stop loss and take profit from Fibonacci levels.

    Parameters
    ----------
    fib_high : float
        High of the Fibonacci range.
    fib_low : float
        Low of the Fibonacci range.
    entry_level : float, optional
        Percentage of the range used to compute the entry price.
    sl_buffer_pips : float, optional
        Additional pips added outside the Fibonacci levels for the stop loss.
    rr_ratio : float, optional
        Desired risk–reward ratio used for the take profit calculation.
    for_sell : bool, optional
        If ``True`` the calculation assumes a sell trade, setting the stop
        loss above ``fib_high`` and the take profit below the entry price.
        If ``False`` it assumes a buy trade with the stop loss below
        ``fib_low`` and the take profit above the entry.
    point : float, optional
        Price value of one pip for the symbol.

    Returns
    -------
    tuple of float
        ``(fib_price, sl, tp)`` where ``fib_price`` is the entry price, ``sl``
        is the stop loss price and ``tp`` is the take profit price.
    """

    fib_price = fib_high - (fib_high - fib_low) * (entry_level / 100.0)
    sl = (
        fib_high + sl_buffer_pips * point
        if for_sell
        else fib_low - sl_buffer_pips * point
    )
    tp = (
        fib_price - (sl - fib_price) * rr_ratio
        if for_sell
        else fib_price + (fib_price - sl) * rr_ratio
    )
    return fib_price, sl, tp
