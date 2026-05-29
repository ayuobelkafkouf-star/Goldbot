"""Modelli dati condivisi fra i 4 agenti.

Ogni agente comunica con il successivo tramite questi oggetti, mantenendo
le responsabilita' separate (analisi -> guardiano -> rischio -> esecuzione).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import List, Optional


class Direction(str, Enum):
    BUY = "BUY"
    SELL = "SELL"
    NONE = "NONE"


@dataclass
class Bar:
    """Singola candela OHLCV."""
    time: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float


@dataclass
class Zone:
    """Zona Supply/Demand."""
    top: float
    bottom: float


@dataclass
class Signal:
    """Output dell'Agente ANALISI: cosa sta facendo il mercato."""
    direction: Direction = Direction.NONE
    score: int = 0
    entry_ref: float = 0.0      # M15 low (BUY) / M15 high (SELL) usato per lo SL
    atr_m15: float = 0.0
    atr_local: float = 0.0
    reasons: List[str] = field(default_factory=list)

    @property
    def has_signal(self) -> bool:
        return self.direction != Direction.NONE


@dataclass
class Permission:
    """Output dell'Agente GUARDIANO: e' il momento giusto per operare?"""
    allowed: bool = True
    reason: str = ""


@dataclass
class RiskPlan:
    """Output dell'Agente RISK: quanto rischiare e dove mettere SL/TP."""
    valid: bool = False
    lots: float = 0.0
    sl: float = 0.0
    tp1: float = 0.0
    tp2: float = 0.0
    reason: str = ""


@dataclass
class Position:
    """Posizione aperta gestita dal broker simulato."""
    direction: Direction
    entry_price: float
    volume: float
    sl: float
    tp: float
    open_time: datetime
    # Stato strategico gestito dall'Esecutore
    tp1_price: float = 0.0
    tp2_price: float = 0.0
    tp1_hit: bool = False
    be_active: bool = False
    trail_sl: float = 0.0
    initial_volume: float = 0.0

    def __post_init__(self):
        if self.initial_volume == 0.0:
            self.initial_volume = self.volume


@dataclass
class TradeResult:
    """Risultato di un trade chiuso, per il diario operazioni."""
    direction: Direction
    entry_price: float
    exit_price: float
    volume: float
    open_time: datetime
    close_time: datetime
    profit: float
    reason: str
