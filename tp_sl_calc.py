import math

def calc_tp_sl(fib_high, fib_low, entry_level=50.0, sl_buffer_pips=10, rr_ratio=3.0, for_sell=False, point=0.0001):
    fib_price = fib_high - (fib_high - fib_low) * (entry_level / 100.0)
    sl = fib_high + sl_buffer_pips * point if for_sell else fib_low - sl_buffer_pips * point
    tp = fib_price - (sl - fib_price) * rr_ratio if for_sell else fib_price + (fib_price - sl) * rr_ratio
    return fib_price, sl, tp
