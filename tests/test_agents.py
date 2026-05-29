"""Test di base per i 4 agenti e l'orchestratore."""
from datetime import datetime, timedelta

from goldbot_agents.agents.analysis import AnalysisAgent, MarketSnapshot
from goldbot_agents.agents.guardian import AccountState, GuardianAgent
from goldbot_agents.agents.risk import RiskAgent, RiskContext
from goldbot_agents.core.config import Config, Mode
from goldbot_agents.core.models import Direction, Signal
from goldbot_agents.data import feed
from goldbot_agents.orchestrator import Orchestrator


def test_guardian_blocks_out_of_hours():
    cfg = Config(mode=Mode.CONSERVATIVE)
    g = GuardianAgent(cfg)
    st = AccountState(eq_peak=10000, day_eq=10000)
    # 03:00 e' fuori dalla sessione overlap 13-17
    perm = g.check(datetime(2024, 1, 1, 3, 0), 10000, atr_local=5.0, st=st)
    assert not perm.allowed


def test_guardian_allows_in_session():
    cfg = Config(mode=Mode.CONSERVATIVE, use_news=False)
    g = GuardianAgent(cfg)
    st = AccountState(eq_peak=10000, day_eq=10000)
    perm = g.check(datetime(2024, 1, 1, 14, 0), 10000, atr_local=5.0, st=st)
    assert perm.allowed


def test_risk_sizing_buy():
    cfg = Config(risk_pct=1.0, contract_size=100.0)
    r = RiskAgent(cfg)
    sig = Signal(direction=Direction.BUY, score=80, entry_ref=2000.0, atr_local=2.0)
    ctx = RiskContext(entry_price=2001.0, equity=10000.0,
                      recent_high_m15=2010.0, recent_low_m15=1995.0,
                      recent_high_h1=2025.0, recent_low_h1=1990.0)
    plan = r.plan(sig, ctx)
    assert plan.valid
    assert plan.lots > 0
    assert plan.sl < ctx.entry_price < plan.tp1 < plan.tp2


def test_risk_rejects_no_signal():
    cfg = Config()
    r = RiskAgent(cfg)
    ctx = RiskContext(2000, 10000, 2010, 1990, 2025, 1980)
    assert not r.plan(Signal(), ctx).valid


def test_analysis_returns_signal_object():
    cfg = Config()
    a = AnalysisAgent(cfg)
    snap = MarketSnapshot(
        time=datetime(2024, 1, 1, 14, 0),
        m15_open=2000, m15_high=2002, m15_low=1998, m15_close=2001,
        m15_high_prev=2001, m15_low_prev=1999,
        h1_ema_fast=2005, h1_ema_slow=2000,
        m15_ema_fast=2002, m15_ema_slow=2000,
        m15_rsi=50, atr_m15=2.0, atr_local=2.0,
        vol_now=100, vol_sma=80,
        m15_highs=[2002] * 9, m15_lows=[1998] * 9,
    )
    sig = a.update(snap)
    assert sig.direction in (Direction.BUY, Direction.SELL, Direction.NONE)


def test_orchestrator_end_to_end():
    cfg = Config(mode=Mode.AGGRESSIVE, use_news=False)
    df_m15 = feed.generate_synthetic(bars=2000, seed=7)
    df = feed.prepare(df_m15, cfg)
    report = Orchestrator(cfg).run(df)
    assert report.n_trades >= 0
    assert report.final_balance > 0
    assert len(report.equity_curve) == len(df) - 1
