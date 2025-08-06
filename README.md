# FOREX

This repository contains utilities for position sizing calculations used by the `QUICKSTRIKE.MQ5` Expert Advisor.

## BoxRangeBreakoutEA

The `SWEEP/nas gbpjpy us500` Expert Advisor now supports risk-based position sizing and improved breakout confirmation:

* `RiskPercent` – percentage of account balance risked per trade. The lot size is calculated automatically using the stop‑loss distance and pip value.
* `UseCandleClose` checks only fully closed candles (shift 1, 2, …) before opening orders, ensuring breakouts are confirmed.

## Running Tests

The unit tests require Python 3 and `unittest`, which is included with the standard library. To execute the test suite run:

```bash
python3 -m unittest discover -s tests
```

This command will run all tests inside the `tests/` directory.

## License

This project is licensed under the [MIT License](LICENSE).
