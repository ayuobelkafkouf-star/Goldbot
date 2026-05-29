"""Fonte dati per la simulazione.

Carica un CSV OHLCV M15 (o ne genera uno sintetico) e pre-calcola tutti gli
indicatori M15 e H1 necessari agli agenti. Predisposto per essere sostituito
da un feed broker reale che produca lo stesso DataFrame.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from ..core.config import Config
from ..core import indicators as ind


REQUIRED = ["open", "high", "low", "close", "volume"]


def load_csv(path: str | Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    cols = {c.lower(): c for c in df.columns}
    time_col = cols.get("time") or cols.get("date") or cols.get("datetime")
    if time_col is None:
        raise ValueError("CSV senza colonna time/date/datetime")
    df = df.rename(columns={c: c.lower() for c in df.columns})
    df["time"] = pd.to_datetime(df[time_col.lower()])
    df = df.set_index("time").sort_index()
    for col in REQUIRED:
        if col not in df.columns:
            raise ValueError(f"CSV manca la colonna '{col}'")
    return df[REQUIRED]


def generate_synthetic(bars: int = 5000, seed: int = 42, start_price: float = 2000.0) -> pd.DataFrame:
    """Genera candele M15 sintetiche realistiche per XAU/USD (random walk + trend)."""
    rng = np.random.default_rng(seed)
    idx = pd.date_range("2024-01-01", periods=bars, freq="15min")
    # Regimi alternati: trend up / down / range, per creare struttura S/D
    returns = np.empty(bars)
    i = 0
    while i < bars:
        length = int(rng.integers(60, 240))      # durata regime (15-60 ore)
        regime = rng.choice([1, -1, 0], p=[0.35, 0.35, 0.30])
        mu = regime * rng.uniform(0.03, 0.10)     # deriva del regime
        sigma = rng.uniform(0.8, 1.6)             # volatilita'
        n = min(length, bars - i)
        returns[i:i + n] = rng.normal(mu, sigma, n)
        i += n
    close = start_price + np.cumsum(returns)
    close = np.maximum(close, 100.0)
    spread = np.abs(rng.normal(0, 1.5, bars)) + 0.5
    high = close + spread
    low = close - spread
    open_ = np.empty(bars)
    open_[0] = close[0]
    open_[1:] = close[:-1]
    high = np.maximum.reduce([high, open_, close])
    low = np.minimum.reduce([low, open_, close])
    volume = rng.integers(50, 500, bars).astype(float)
    return pd.DataFrame(
        {"open": open_, "high": high, "low": low, "close": close, "volume": volume},
        index=idx,
    )


def prepare(df_m15: pd.DataFrame, cfg: Config) -> pd.DataFrame:
    """Aggiunge tutte le colonne indicatore (M15 + H1 allineato) al DataFrame M15."""
    out = df_m15.copy()
    out.index.name = "time"
    out["ema_fast"] = ind.ema(out["close"], cfg.m15_fast)
    out["ema_slow"] = ind.ema(out["close"], cfg.m15_slow)
    out["rsi"] = ind.rsi(out["close"], cfg.rsi_len)
    out["atr"] = ind.atr(out, 14)
    out["vol_sma"] = out["volume"].rolling(20).mean().shift(1)
    out["recent_high_m15"] = out["high"].rolling(20).max()
    out["recent_low_m15"] = out["low"].rolling(20).min()

    # H1 ricostruito e allineato (valori dell'ultima H1 *chiusa* via merge_asof)
    h1 = ind.resample_h1(df_m15)
    h1["ema_fast"] = ind.ema(h1["close"], cfg.h1_fast)
    h1["ema_slow"] = ind.ema(h1["close"], cfg.h1_slow)
    h1["recent_high_h1"] = h1["high"].rolling(20).max()
    h1["recent_low_h1"] = h1["low"].rolling(20).min()
    # Disponibile solo dopo la chiusura della barra H1: +1h
    h1_avail = h1[["ema_fast", "ema_slow", "recent_high_h1", "recent_low_h1"]].copy()
    h1_avail.index = h1_avail.index + pd.Timedelta(hours=1)
    h1_avail.index.name = "time"
    h1_avail = h1_avail.rename(columns={"ema_fast": "h1_ema_fast", "ema_slow": "h1_ema_slow"})

    out = pd.merge_asof(
        out.reset_index(),
        h1_avail.reset_index(),
        on="time",
        direction="backward",
    ).set_index("time")

    return out.dropna()
