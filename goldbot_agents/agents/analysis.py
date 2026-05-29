"""AGENTE 1 - ANALISI (Signal Engine).

Decide COSA sta facendo il mercato. Non sa nulla di soldi ne' di ordini.
Mantiene lo stato delle zone Supply/Demand e produce un Signal con score.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import List

from ..core.config import Config
from ..core.models import Direction, Signal, Zone


@dataclass
class MarketSnapshot:
    """Fotografia del mercato sulla barra M15 appena chiusa."""
    time: datetime
    m15_open: float
    m15_high: float
    m15_low: float
    m15_close: float
    m15_high_prev: float
    m15_low_prev: float
    h1_ema_fast: float
    h1_ema_slow: float
    m15_ema_fast: float
    m15_ema_slow: float
    m15_rsi: float
    atr_m15: float
    atr_local: float
    vol_now: float
    vol_sma: float
    # Storico per pivot (ordine: dal piu' vecchio al piu' recente)
    m15_highs: List[float] = field(default_factory=list)
    m15_lows: List[float] = field(default_factory=list)


class AnalysisAgent:
    def __init__(self, config: Config):
        self.cfg = config
        self.supply: List[Zone] = []
        self.demand: List[Zone] = []

    # ----------------------------- zone S/D -------------------------------
    def _detect_pivot_high(self, highs: List[float]) -> float | None:
        left, right = self.cfg.pivot_left, self.cfg.pivot_right
        need = left + right + 1
        if len(highs) < need:
            return None
        window = highs[-need:]
        candidate = window[left]
        for i, h in enumerate(window):
            if i == left:
                continue
            if h >= candidate:
                return None
        return candidate

    def _detect_pivot_low(self, lows: List[float]) -> float | None:
        left, right = self.cfg.pivot_left, self.cfg.pivot_right
        need = left + right + 1
        if len(lows) < need:
            return None
        window = lows[-need:]
        candidate = window[left]
        for i, l in enumerate(window):
            if i == left:
                continue
            if l <= candidate:
                return None
        return candidate

    def _push_supply(self, pivot_high: float, atr: float) -> None:
        self.supply.append(Zone(top=pivot_high, bottom=pivot_high - atr * self.cfg.zone_width))
        while len(self.supply) > self.cfg.max_zones:
            self.supply.pop(0)

    def _push_demand(self, pivot_low: float, atr: float) -> None:
        self.demand.append(Zone(top=pivot_low + atr * self.cfg.zone_width, bottom=pivot_low))
        while len(self.demand) > self.cfg.max_zones:
            self.demand.pop(0)

    def _invalidate(self, close: float, atr: float) -> None:
        self.supply = [z for z in self.supply if close <= z.top + atr * 0.5]
        self.demand = [z for z in self.demand if close >= z.bottom - atr * 0.5]

    def _at_supply(self, high: float, atr: float) -> bool:
        tol = self.cfg.eff_zone_tol
        return any(z.bottom - atr * tol <= high <= z.top + atr * tol for z in self.supply)

    def _at_demand(self, low: float, atr: float) -> bool:
        tol = self.cfg.eff_zone_tol
        return any(z.bottom - atr * tol <= low <= z.top + atr * tol for z in self.demand)

    # ------------------------------ update --------------------------------
    def update(self, s: MarketSnapshot) -> Signal:
        cfg = self.cfg

        # 1) aggiorna zone
        ph = self._detect_pivot_high(s.m15_highs)
        pl = self._detect_pivot_low(s.m15_lows)
        if ph is not None:
            self._push_supply(ph, s.atr_m15)
        if pl is not None:
            self._push_demand(pl, s.atr_m15)
        self._invalidate(s.m15_close, s.atr_m15)

        # 2) trend
        h1_bull = s.h1_ema_fast > s.h1_ema_slow
        h1_bear = s.h1_ema_fast < s.h1_ema_slow
        m15_bull = s.m15_ema_fast > s.m15_ema_slow
        m15_bear = s.m15_ema_fast < s.m15_ema_slow

        # 3) retest zona
        at_supply = self._at_supply(s.m15_high, s.atr_m15)
        at_demand = self._at_demand(s.m15_low, s.atr_m15)

        # 4) spike + candela di conferma
        rng = s.m15_high - s.m15_low
        spike_up = rng >= s.atr_m15 * cfg.spike_mult and s.m15_high > s.m15_high_prev
        spike_down = rng >= s.atr_m15 * cfg.spike_mult and s.m15_low < s.m15_low_prev
        body_sell = s.m15_open - s.m15_close
        body_buy = s.m15_close - s.m15_open
        confirm_sell = spike_up and s.m15_close < s.m15_open and body_sell >= s.atr_m15 * cfg.body_mult
        confirm_buy = spike_down and s.m15_close > s.m15_open and body_buy >= s.atr_m15 * cfg.body_mult

        # 5) RSI
        rsi_ok_sell = 45 < s.m15_rsi < cfg.rsi_ob
        rsi_ok_buy = cfg.rsi_os < s.m15_rsi < 55

        # 6) score
        vol_high = s.vol_sma > 0 and s.vol_now > s.vol_sma * 1.2
        atr_ok = (not cfg.use_atr) or s.atr_local >= cfg.atr_min

        score_sell = score_buy = 0
        if h1_bear:
            score_sell += 25
        if h1_bull:
            score_buy += 25
        if m15_bear:
            score_sell += 20
        if m15_bull:
            score_buy += 20
        if at_supply:
            score_sell += 20
        if at_demand:
            score_buy += 20
        if rsi_ok_sell:
            score_sell += 15
        if rsi_ok_buy:
            score_buy += 15
        if vol_high:
            score_sell += 10
            score_buy += 10
        if atr_ok:
            score_sell += 10
            score_buy += 10

        # 7) segnale finale (parte tecnica; orari/news li valuta il Guardiano)
        sig = Signal(atr_m15=s.atr_m15, atr_local=s.atr_local)

        sell_ready = (
            confirm_sell and at_supply and h1_bear and m15_bear and rsi_ok_sell
            and score_sell >= cfg.eff_min_score
        )
        buy_ready = (
            confirm_buy and at_demand and h1_bull and m15_bull and rsi_ok_buy
            and score_buy >= cfg.eff_min_score
        )

        if buy_ready and (not sell_ready or score_buy >= score_sell):
            sig.direction = Direction.BUY
            sig.score = score_buy
            sig.entry_ref = s.m15_low
            sig.reasons = ["H1 bull", "M15 bull", "demand retest", "spike+confirm"]
        elif sell_ready:
            sig.direction = Direction.SELL
            sig.score = score_sell
            sig.entry_ref = s.m15_high
            sig.reasons = ["H1 bear", "M15 bear", "supply retest", "spike+confirm"]

        return sig
