# FOREX

This repository contains the **QUICKSTRIKE.MQ5** Expert Advisor and a couple of Python helpers used to validate its trading calculations.

## Project Components

### `SWEEP/QUICKSTRIKE.MQ5`
The MQL5 source implements an "Asian Liquidity Sweep" trading strategy. It detects fractal breakouts during the Asian session and places stop or limit orders based on Fibonacci levels. The EA uses the same lot sizing and price calculations that are mirrored in the accompanying Python scripts.

### `calculate_lots.py`
Standalone Python implementation of the position sizing logic. Given a stop‑loss distance in pips, it returns the trade volume while respecting account balance, broker step size and min/max lot limits.

### `tp_sl_calc.py`
Helper function that computes entry, stop loss and take profit prices from a Fibonacci range. The EA relies on this logic internally and the Python version allows it to be unit tested.

The Python modules do **not** run inside MetaTrader; they simply replicate the EA’s key math so the behaviour can be tested with `unittest`.

## Compiling and Installing the EA
1. Copy `SWEEP/QUICKSTRIKE.MQ5` to your MetaTrader 5 `MQL5/Experts` folder.
2. Open MetaEditor, load the file and press **Compile**. This produces `QUICKSTRIKE.ex5` in the same directory.
3. Restart MetaTrader 5 or refresh the *Navigator* pane so the EA appears under *Experts*.
4. Drag `QUICKSTRIKE` onto a chart and adjust the inputs as desired.

## Running Tests
The unit tests require Python 3 and the standard `unittest` library. Execute all tests with:

```bash
python3 -m unittest discover -s tests
```

This command runs every test inside the `tests/` directory.
