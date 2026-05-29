"""Broker simulato per paper trading su dati CSV.

Tiene un saldo virtuale, apre/chiude una posizione alla volta e verifica
il raggiungimento di SL/TP barra per barra usando high/low.
"""
from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from ..core.config import Config
from ..core.models import Bar, Direction, Position, TradeResult
from .base import Broker


class PaperBroker(Broker):
    def __init__(self, config: Config):
        self.cfg = config
        self._balance = config.initial_balance
        self._pos: Optional[Position] = None
        self.trades: List[TradeResult] = []
        self._last_bar: Optional[Bar] = None

    # ----------------------------- proprieta' -----------------------------
    @property
    def balance(self) -> float:
        return self._balance

    @property
    def equity(self) -> float:
        """Saldo + P&L flottante della posizione aperta (mark-to-market)."""
        if self._pos is None or self._last_bar is None:
            return self._balance
        return self._balance + self._floating_pl(self._last_bar.close)

    def position(self) -> Optional[Position]:
        return self._pos

    # ------------------------------ trading -------------------------------
    def open(self, direction: Direction, volume: float, sl: float, tp: float) -> Optional[Position]:
        if self._pos is not None or volume <= 0 or self._last_bar is None:
            return None
        # Entry al prezzo di chiusura corrente +/- meta' spread
        price = self._last_bar.close
        entry = price + self.cfg.spread / 2 if direction == Direction.BUY else price - self.cfg.spread / 2
        self._pos = Position(
            direction=direction,
            entry_price=entry,
            volume=volume,
            sl=sl,
            tp=tp,
            open_time=self._last_bar.time,
            initial_volume=volume,
        )
        return self._pos

    def modify(self, sl: float, tp: float) -> None:
        if self._pos is not None:
            self._pos.sl = sl
            self._pos.tp = tp

    def close_partial(self, volume: float, reason: str = "partial") -> None:
        if self._pos is None or self._last_bar is None:
            return
        volume = min(volume, self._pos.volume)
        if volume <= 0:
            return
        price = self._last_bar.close
        self._realize(price, volume, reason)
        self._pos.volume -= volume
        if self._pos.volume <= 1e-9:
            self._pos = None

    def close_all(self, reason: str = "manual") -> None:
        if self._pos is None or self._last_bar is None:
            return
        self._realize(self._last_bar.close, self._pos.volume, reason)
        self._pos = None

    # ----------------------------- simulazione ----------------------------
    def on_bar(self, bar: Bar) -> Optional[TradeResult]:
        """Aggiorna il broker con una nuova barra; chiude su SL/TP se toccati.

        Restituisce il TradeResult se la posizione e' stata chiusa, altrimenti None.
        """
        self._last_bar = bar
        if self._pos is None:
            return None

        pos = self._pos
        if pos.direction == Direction.BUY:
            # SL ha priorita' (scenario peggiore) se la barra tocca entrambi
            if bar.low <= pos.sl:
                return self._close_at(pos.sl, "SL")
            if pos.tp > 0 and bar.high >= pos.tp:
                return self._close_at(pos.tp, "TP")
        else:  # SELL
            if bar.high >= pos.sl:
                return self._close_at(pos.sl, "SL")
            if pos.tp > 0 and bar.low <= pos.tp:
                return self._close_at(pos.tp, "TP")
        return None

    # ------------------------------ interni -------------------------------
    def _floating_pl(self, price: float) -> float:
        pos = self._pos
        if pos is None:
            return 0.0
        diff = price - pos.entry_price if pos.direction == Direction.BUY else pos.entry_price - price
        return diff * pos.volume * self.cfg.contract_size

    def _realize(self, price: float, volume: float, reason: str) -> None:
        pos = self._pos
        diff = price - pos.entry_price if pos.direction == Direction.BUY else pos.entry_price - price
        profit = diff * volume * self.cfg.contract_size
        self._balance += profit
        self.trades.append(
            TradeResult(
                direction=pos.direction,
                entry_price=pos.entry_price,
                exit_price=price,
                volume=volume,
                open_time=pos.open_time,
                close_time=self._last_bar.time,
                profit=profit,
                reason=reason,
            )
        )

    def _close_at(self, price: float, reason: str) -> TradeResult:
        self._realize(price, self._pos.volume, reason)
        result = self.trades[-1]
        self._pos = None
        return result
