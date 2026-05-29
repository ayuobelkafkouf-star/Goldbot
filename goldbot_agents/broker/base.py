"""Interfaccia astratta del broker.

L'Agente ESECUTORE parla solo con questa interfaccia: per passare dal paper
trading a un broker reale (MT5, ccxt, ...) basta implementare una nuova
sottoclasse senza toccare gli agenti.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Optional

from ..core.models import Direction, Position


class Broker(ABC):
    @property
    @abstractmethod
    def equity(self) -> float:
        ...

    @property
    @abstractmethod
    def balance(self) -> float:
        ...

    @abstractmethod
    def position(self) -> Optional[Position]:
        """Posizione aperta corrente (uno strumento singolo) o None."""

    @abstractmethod
    def open(self, direction: Direction, volume: float, sl: float, tp: float) -> Optional[Position]:
        ...

    @abstractmethod
    def modify(self, sl: float, tp: float) -> None:
        ...

    @abstractmethod
    def close_partial(self, volume: float, reason: str = "partial") -> None:
        ...

    @abstractmethod
    def close_all(self, reason: str = "manual") -> None:
        ...
