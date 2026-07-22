//+------------------------------------------------------------------+
//|                                              GoldBot_XAUUSD.mq5  |
//|              Strategia ICT pura: Liquidity Sweep + CiSD          |
//+------------------------------------------------------------------+
#property copyright "GoldBot ICT MQL5"
#property version   "6.00"
#property strict
#property description "GoldBot XAUUSD - Strategia ICT: Liquidity Sweep + CiSD, risk dinamico, trailing ATR"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade        Trade;
CPositionInfo Pos;
CSymbolInfo   Sym;

//============================ INPUTS ===============================
enum ENUM_MODE { MODE_CONSERVATIVE, MODE_EXTENDED, MODE_AGGRESSIVE };

input group "═══ Modalità ═══"
input ENUM_MODE InpMode        = MODE_CONSERVATIVE; // Modalità operativa

input group "═══ ICT: Liquidity Sweep + CiSD ═══"
input int       InpLiqLookback  = 20;   // Barre lookback pool liquidità
input double    InpLiqBufferAtr = 0.1;  // Buffer sweep oltre il livello (ATR)
input double    InpCisdBodyMult = 0.3;  // Displacement: corpo minimo CiSD (ATR)

input group "═══ Rischio ═══"
input double    InpRiskPct     = 0.5;  // Rischio % per trade
input double    InpSLAtrMult   = 0.4;  // SL buffer ATR
input int       InpTP1Pct      = 70;   // % chiusura TP1
input bool      InpUseBE       = true; // Break-even dopo TP1
input bool      InpUseTrail    = true; // Trailing stop ATR dopo TP1
input double    InpTrailMult   = 1.5;  // Trailing ATR multiplier

input group "═══ Sessione ═══"
input int       InpSessionStart= 13;   // Sessione overlap start (Roma)
input int       InpSessionEnd  = 17;   // Sessione overlap end
input int       InpStartHour   = 8;    // Estesa/Aggressiva: ora inizio
input int       InpEndHour     = 20;   // Estesa/Aggressiva: ora fine

input group "═══ Protezione ═══"
input bool      InpUseCircuit  = true; // Circuit breaker drawdown
input double    InpDDThreshold = 5.0;  // DD max % dal peak
input int       InpPauseDays   = 3;    // Giorni pausa dopo trigger

input group "═══ Filtri ═══"
input bool      InpUseATR      = true; // Filtro ATR minimo
input double    InpATRMin      = 1.5;  // ATR minimo
input int       InpCooldownBars= 5;    // Cooldown barre M15
input int       InpMaxTradesDay= 5;    // Max trade giorno
input double    InpMaxLoss     = 1.0;  // Max perdita % giorno
input double    InpMaxProfit   = 5.0;  // Max profitto % giorno

input group "═══ Notizie ═══"
input bool      InpUseNews     = true; // Filtro notizie
input bool      InpNews1Active = true; // Notizia 1 (NFP/CPI)
input int       InpNews1Hour   = 14;   // Ora notizia 1
input int       InpNews1Min    = 30;   // Min notizia 1
input bool      InpNews2Active = false;// Notizia 2 (FOMC)
input int       InpNews2Hour   = 20;
input int       InpNews2Min    = 0;
input bool      InpNews3Active = false;// Notizia 3
input int       InpNews3Hour   = 16;
input int       InpNews3Min    = 0;
input int       InpNewsBefore  = 30;   // Minuti prima notizia
input int       InpNewsAfter   = 30;   // Minuti dopo notizia

input group "═══ Esecuzione ═══"
input ulong     InpMagic       = 20260523; // Magic Number
input int       InpSlippagePts = 30;   // Slippage in punti

//============================ GLOBALS ==============================
// Handle indicatori
int h_m15_atr, h_atr_local;

// State
datetime g_last_m15_bar = 0;
datetime g_last_close_time = 0;
int      g_trades_today = 0;
int      g_last_day = -1;
int      g_day_counter = 0;
int      g_pause_until_d = 0;
double   g_eq_peak = 0;
double   g_day_eq = 0;

// Position state
bool     g_be_active = false;
double   g_trail_sl  = 0;
double   g_entry_px  = 0;
double   g_tp1_px    = 0;
double   g_tp2_px    = 0;
double   g_sl_px     = 0;
bool     g_tp1_hit   = false;
bool     g_is_long   = false;

// Liquidity sweep + CiSD state
bool     g_liq_sweep_sell = false; // buy-side liquidity grab + rigetto → SELL
bool     g_liq_sweep_buy  = false; // sell-side liquidity grab + rigetto → BUY
double   g_bsl_level      = 0;     // buy-side liquidity pool
double   g_ssl_level      = 0;     // sell-side liquidity pool

// Effective values (set per modalità)
bool   g_eff_use_session;
bool   g_eff_force_hours;
int    g_eff_cooldown;
int    g_eff_max_trades;

// Timezone offset (server vs Europe/Rome)
int g_tz_offset_hours = 0;

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!Sym.Name(_Symbol)) return INIT_FAILED;
   Sym.RefreshRates();

   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints((ulong)InpSlippagePts);
   Trade.SetTypeFillingBySymbol(_Symbol);
   Trade.SetMarginMode();

   h_m15_atr  = iATR(_Symbol, PERIOD_M15, 14);
   h_atr_local= iATR(_Symbol, _Period,    14);

   if(h_m15_atr==INVALID_HANDLE || h_atr_local==INVALID_HANDLE)
   {
      Print("Errore creazione handles indicatori");
      return INIT_FAILED;
   }

   g_eq_peak = AccountInfoDouble(ACCOUNT_EQUITY);
   g_day_eq  = g_eq_peak;

   ApplyMode();
   ComputeTzOffset();

   Comment("GoldBot ICT MQL5 inizializzato — modalità: ", ModeName());
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_m15_atr);
   IndicatorRelease(h_atr_local);
   Comment("");
}

//+------------------------------------------------------------------+
//| ONTICK                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageOpenPositions();

   datetime cur_m15 = iTime(_Symbol, PERIOD_M15, 0);
   if(cur_m15 == g_last_m15_bar) return;
   g_last_m15_bar = cur_m15;

   ApplyMode();
   ProcessNewBar();
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Imposta valori effettivi in base alla modalità                    |
//+------------------------------------------------------------------+
void ApplyMode()
{
   bool is_cons = (InpMode == MODE_CONSERVATIVE);
   bool is_ext  = (InpMode == MODE_EXTENDED);
   bool is_aggr = (InpMode == MODE_AGGRESSIVE);

   g_eff_use_session = is_cons;
   g_eff_force_hours = is_ext || is_aggr;
   g_eff_cooldown    = is_aggr ? 2  : InpCooldownBars;
   g_eff_max_trades  = is_aggr ? 10 : InpMaxTradesDay;
}

string ModeName()
{
   if(InpMode==MODE_CONSERVATIVE) return "Conservativo";
   if(InpMode==MODE_EXTENDED)     return "Sessione Estesa";
   return "Aggressivo";
}

//+------------------------------------------------------------------+
//| Differenza fra ora server e Europe/Rome (approssimata)            |
//+------------------------------------------------------------------+
void ComputeTzOffset()
{
   datetime gmt = TimeGMT();
   datetime srv = TimeCurrent();
   int diff = (int)((srv - gmt) / 3600);
   // Europe/Rome = GMT+1 (inverno) / GMT+2 (estate, CEST)
   MqlDateTime g; TimeToStruct(gmt, g);
   int rome_offset = (g.mon >= 4 && g.mon <= 10) ? 2 : 1;
   g_tz_offset_hours = rome_offset - diff;
}

int RomeHour(datetime t)
{
   MqlDateTime st;
   TimeToStruct(t, st);
   int h = st.hour + g_tz_offset_hours;
   if(h < 0) h += 24;
   if(h >= 24) h -= 24;
   return h;
}

int RomeMinute(datetime t)
{
   MqlDateTime st;
   TimeToStruct(t, st);
   return st.min;
}

int RomeDay(datetime t)
{
   MqlDateTime st;
   datetime adjusted = t + g_tz_offset_hours * 3600;
   TimeToStruct(adjusted, st);
   return st.day;
}

//+------------------------------------------------------------------+
//| Helper: copia 1 valore da buffer al bar idx (idx=1 = closed bar)  |
//+------------------------------------------------------------------+
bool GetBuf(int handle, int shift, double &out)
{
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0) return false;
   out = buf[0];
   return true;
}

//+------------------------------------------------------------------+
//| Liquidity Sweep + CiSD                                            |
//| Buy-side liquidity  = massimo dei bar precedenti (stop dei buy)   |
//| Sell-side liquidity = minimo dei bar precedenti (stop dei sell)   |
//| Sweep+CiSD: il bar wicka OLTRE il pool ma RICHIUDE dall'altra      |
//| parte con corpo direzionale (displacement) = cambio di stato di   |
//| consegna → segnale di ingresso.                                   |
//+------------------------------------------------------------------+
void DetectLiquiditySweep(double atr_m15)
{
   g_liq_sweep_sell = false;
   g_liq_sweep_buy  = false;
   g_bsl_level = 0;
   g_ssl_level = 0;
   if(atr_m15 <= 0) return;

   // Pool calcolati sui bar precedenti al bar di sweep (shift 2..lookback+1)
   int hi_idx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, InpLiqLookback, 2);
   int lo_idx = iLowest (_Symbol, PERIOD_M15, MODE_LOW,  InpLiqLookback, 2);
   if(hi_idx < 0 || lo_idx < 0) return;

   g_bsl_level = iHigh(_Symbol, PERIOD_M15, hi_idx); // buy-side liquidity
   g_ssl_level = iLow (_Symbol, PERIOD_M15, lo_idx); // sell-side liquidity

   double o = iOpen (_Symbol, PERIOD_M15, 1);
   double h = iHigh (_Symbol, PERIOD_M15, 1);
   double l = iLow  (_Symbol, PERIOD_M15, 1);
   double c = iClose(_Symbol, PERIOD_M15, 1);
   double buf  = atr_m15 * InpLiqBufferAtr;
   double body = MathAbs(c - o);
   bool   displaced = body >= atr_m15 * InpCisdBodyMult;

   // Sweep della buy-side liquidity + rigetto ribassista (CiSD down) → SELL
   if(h > g_bsl_level + buf && c < g_bsl_level && c < o && displaced)
      g_liq_sweep_sell = true;

   // Sweep della sell-side liquidity + rigetto rialzista (CiSD up) → BUY
   if(l < g_ssl_level - buf && c > g_ssl_level && c > o && displaced)
      g_liq_sweep_buy = true;
}

//+------------------------------------------------------------------+
//| Process new closed M15 bar                                        |
//+------------------------------------------------------------------+
void ProcessNewBar()
{
   double m15_atr_v, atr_local;
   if(!GetBuf(h_m15_atr, 1, m15_atr_v)) return;
   if(!GetBuf(h_atr_local,1, atr_local))return;

   // Segnale di ingresso: liquidity sweep + CiSD sul bar appena chiuso
   DetectLiquiditySweep(m15_atr_v);

   double m15_h = iHigh(_Symbol, PERIOD_M15, 1);
   double m15_l = iLow (_Symbol, PERIOD_M15, 1);

   // Filtri temporali
   datetime now = TimeCurrent();
   int h_rome = RomeHour(now);
   int m_rome = RomeMinute(now);

   bool session_ok = (h_rome >= InpSessionStart && h_rome < InpSessionEnd);
   bool hours_ok   = (h_rome >= InpStartHour    && h_rome < InpEndHour);
   bool hour_ok    = g_eff_use_session ? session_ok : (g_eff_force_hours ? hours_ok : true);

   bool atr_ok     = !InpUseATR || atr_local >= InpATRMin;
   bool news_ok    = !InpUseNews || !IsNewsTime(h_rome, m_rome);

   // Day rollover
   int cur_day = RomeDay(now);
   if(cur_day != g_last_day)
   {
      g_trades_today = 0;
      g_last_day     = cur_day;
      g_day_counter += 1;
      g_day_eq       = AccountInfoDouble(ACCOUNT_EQUITY);
   }

   bool cooldown_ok = (now - g_last_close_time) >= (g_eff_cooldown * PeriodSeconds(PERIOD_M15));
   bool trades_ok   = g_trades_today < g_eff_max_trades;

   double eq      = AccountInfoDouble(ACCOUNT_EQUITY);
   double day_pct = g_day_eq > 0 ? (eq - g_day_eq) / g_day_eq * 100.0 : 0;
   bool day_ok    = day_pct > -InpMaxLoss && day_pct < InpMaxProfit;

   // Circuit breaker
   if(eq > g_eq_peak) g_eq_peak = eq;
   double dd_pct = g_eq_peak > 0 ? (g_eq_peak - eq) / g_eq_peak * 100.0 : 0;
   if(InpUseCircuit && dd_pct >= InpDDThreshold && g_day_counter >= g_pause_until_d)
      g_pause_until_d = g_day_counter + InpPauseDays;
   bool circuit_ok = !InpUseCircuit || g_day_counter >= g_pause_until_d;

   // Filtri di sicurezza comuni
   bool no_position = !HasOpenPosition();
   bool common_ok   = hour_ok && atr_ok && news_ok && cooldown_ok && trades_ok &&
                      day_ok && circuit_ok && no_position;

   // Segnali finali: SOLO liquidity sweep + CiSD
   bool final_sell = g_liq_sweep_sell && common_ok;
   bool final_buy  = g_liq_sweep_buy  && common_ok;

   if(final_buy)  OpenLong (m15_l, m15_atr_v, atr_local);
   if(final_sell) OpenShort(m15_h, m15_atr_v, atr_local);
}

//+------------------------------------------------------------------+
//| News filter                                                       |
//+------------------------------------------------------------------+
bool IsNewsTime(int h_rome, int m_rome)
{
   int cur = h_rome*60 + m_rome;
   if(InpNews1Active)
   {
      int n = InpNews1Hour*60 + InpNews1Min;
      if(cur >= n - InpNewsBefore && cur <= n + InpNewsAfter) return true;
   }
   if(InpNews2Active)
   {
      int n = InpNews2Hour*60 + InpNews2Min;
      if(cur >= n - InpNewsBefore && cur <= n + InpNewsAfter) return true;
   }
   if(InpNews3Active)
   {
      int n = InpNews3Hour*60 + InpNews3Min;
      if(cur >= n - InpNewsBefore && cur <= n + InpNewsAfter) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Position helpers                                                  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(Pos.SelectByIndex(i))
         if(Pos.Symbol() == _Symbol && Pos.Magic() == InpMagic)
            return true;
   }
   return false;
}

bool GetOpenPosition(ulong &ticket_out, ENUM_POSITION_TYPE &type_out, double &volume_out)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(Pos.SelectByIndex(i))
         if(Pos.Symbol() == _Symbol && Pos.Magic() == InpMagic)
         {
            ticket_out = Pos.Ticket();
            type_out   = Pos.PositionType();
            volume_out = Pos.Volume();
            return true;
         }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Position sizing dinamico                                          |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance_price)
{
   if(sl_distance_price <= 0) return 0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_cash = equity * InpRiskPct / 100.0;

   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0 || tick_value <= 0) return 0;

   double loss_per_lot = (sl_distance_price / tick_size) * tick_value;
   if(loss_per_lot <= 0) return 0;

   double lots = risk_cash / loss_per_lot;

   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lot_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lots = MathFloor(lots / lot_step) * lot_step;
   if(lots < lot_min) lots = lot_min;
   if(lots > lot_max) lots = lot_max;
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Apertura ordini                                                   |
//| SL oltre lo sweep (dove è stata presa la liquidità);              |
//| TP verso la liquidità opposta (struttura M15 / H1).               |
//+------------------------------------------------------------------+
void OpenLong(double m15_low, double atr_m15, double atr_local)
{
   Sym.RefreshRates();
   double price = Sym.Ask();
   double sl    = m15_low - atr_local * InpSLAtrMult;
   // TP1 = struct high M15, TP2 = struct high H1 (buy-side liquidity opposta)
   double tp1 = iHigh(_Symbol, PERIOD_M15, iHighest(_Symbol, PERIOD_M15, MODE_HIGH, 20, 1));
   double tp2 = iHigh(_Symbol, PERIOD_H1,  iHighest(_Symbol, PERIOD_H1,  MODE_HIGH, 20, 1));
   if(tp1 <= price || tp2 <= tp1) return; // sanity

   double lots = CalculateLotSize(price - sl);
   if(lots <= 0) return;

   if(Trade.Buy(lots, _Symbol, price, sl, tp2, "GoldBot ICT BUY"))
   {
      g_entry_px = price;
      g_sl_px    = sl;
      g_tp1_px   = tp1;
      g_tp2_px   = tp2;
      g_is_long  = true;
      g_be_active= false;
      g_tp1_hit  = false;
      g_trail_sl = 0;
   }
}

void OpenShort(double m15_high, double atr_m15, double atr_local)
{
   Sym.RefreshRates();
   double price = Sym.Bid();
   double sl    = m15_high + atr_local * InpSLAtrMult;
   double tp1 = iLow(_Symbol, PERIOD_M15, iLowest(_Symbol, PERIOD_M15, MODE_LOW, 20, 1));
   double tp2 = iLow(_Symbol, PERIOD_H1,  iLowest(_Symbol, PERIOD_H1,  MODE_LOW, 20, 1));
   if(tp1 >= price || tp2 >= tp1) return;

   double lots = CalculateLotSize(sl - price);
   if(lots <= 0) return;

   if(Trade.Sell(lots, _Symbol, price, sl, tp2, "GoldBot ICT SELL"))
   {
      g_entry_px = price;
      g_sl_px    = sl;
      g_tp1_px   = tp1;
      g_tp2_px   = tp2;
      g_is_long  = false;
      g_be_active= false;
      g_tp1_hit  = false;
      g_trail_sl = 0;
   }
}

//+------------------------------------------------------------------+
//| Gestione posizioni: TP1 parziale + BE + trailing                  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   ulong ticket; ENUM_POSITION_TYPE ptype; double vol;
   bool has = GetOpenPosition(ticket, ptype, vol);

   // Cleanup quando non c'è più la posizione
   if(!has)
   {
      if(g_tp1_hit || g_entry_px != 0)
      {
         g_last_close_time = TimeCurrent();
         g_trades_today++;
         g_entry_px = 0;
         g_sl_px = 0;
         g_tp1_px = 0;
         g_tp2_px = 0;
         g_be_active = false;
         g_tp1_hit = false;
         g_trail_sl = 0;
      }
      return;
   }

   Sym.RefreshRates();
   double bid = Sym.Bid();
   double ask = Sym.Ask();

   // ---------- LONG ----------
   if(ptype == POSITION_TYPE_BUY)
   {
      // TP1 parziale
      if(!g_tp1_hit && g_tp1_px > 0 && bid >= g_tp1_px)
      {
         double close_vol = NormalizeDouble(vol * InpTP1Pct / 100.0, 2);
         double lot_step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         close_vol = MathFloor(close_vol / lot_step) * lot_step;
         if(close_vol > 0 && close_vol < vol)
         {
            if(Trade.PositionClosePartial(_Symbol, close_vol))
            {
               g_tp1_hit = true;
               if(InpUseBE)
               {
                  g_be_active = true;
                  g_trail_sl  = g_entry_px;
                  Trade.PositionModify(_Symbol, g_trail_sl, g_tp2_px);
               }
            }
         }
      }
      // Trailing
      if(InpUseTrail && g_be_active)
      {
         double atr_l = 0; GetBuf(h_atr_local, 0, atr_l);
         double new_sl = bid - atr_l * InpTrailMult;
         if(new_sl > g_trail_sl && new_sl > g_entry_px)
         {
            g_trail_sl = new_sl;
            Trade.PositionModify(_Symbol, g_trail_sl, g_tp2_px);
         }
      }
   }
   // ---------- SHORT ----------
   else if(ptype == POSITION_TYPE_SELL)
   {
      if(!g_tp1_hit && g_tp1_px > 0 && ask <= g_tp1_px)
      {
         double close_vol = NormalizeDouble(vol * InpTP1Pct / 100.0, 2);
         double lot_step  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         close_vol = MathFloor(close_vol / lot_step) * lot_step;
         if(close_vol > 0 && close_vol < vol)
         {
            if(Trade.PositionClosePartial(_Symbol, close_vol))
            {
               g_tp1_hit = true;
               if(InpUseBE)
               {
                  g_be_active = true;
                  g_trail_sl  = g_entry_px;
                  Trade.PositionModify(_Symbol, g_trail_sl, g_tp2_px);
               }
            }
         }
      }
      if(InpUseTrail && g_be_active)
      {
         double atr_l = 0; GetBuf(h_atr_local, 0, atr_l);
         double new_sl = ask + atr_l * InpTrailMult;
         if((g_trail_sl == 0 || new_sl < g_trail_sl) && new_sl < g_entry_px)
         {
            g_trail_sl = new_sl;
            Trade.PositionModify(_Symbol, g_trail_sl, g_tp2_px);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard via Comment()                                            |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd_pct = g_eq_peak > 0 ? (g_eq_peak - eq) / g_eq_peak * 100.0 : 0;
   double day_pct = g_day_eq > 0 ? (eq - g_day_eq) / g_day_eq * 100.0 : 0;
   int pause_left = MathMax(0, g_pause_until_d - g_day_counter);

   string liq = g_liq_sweep_sell ? "SWEEP SELL ▼" : (g_liq_sweep_buy ? "SWEEP BUY ▲" : "in attesa…");

   string status = "";
   status += "═══ GoldBot ICT MQL5 ═══\n";
   status += "Strategia: Liquidity Sweep + CiSD\n";
   status += "Modalità: " + ModeName() + "\n";
   status += "Equity: "   + DoubleToString(eq, 2) + "\n";
   status += "P&L oggi: " + DoubleToString(day_pct, 2) + "%\n";
   status += "Trade oggi: " + IntegerToString(g_trades_today) + "/" + IntegerToString(g_eff_max_trades) + "\n";
   status += "DD dal peak: " + DoubleToString(dd_pct, 2) + "%\n";
   status += "Status: " + (pause_left>0 ? ("PAUSED " + IntegerToString(pause_left) + "g") : "ACTIVE") + "\n";
   status += "Buy-side liq: "  + DoubleToString(g_bsl_level, 2) + "\n";
   status += "Sell-side liq: " + DoubleToString(g_ssl_level, 2) + "\n";
   status += "Segnale: " + liq + "\n";
   if(HasOpenPosition())
   {
      status += "Posizione: " + (g_is_long ? "LONG" : "SHORT");
      if(g_be_active) status += " (BE" + (InpUseTrail ? "+TRAIL" : "") + ")";
      status += "\n";
      status += "SL: " + DoubleToString(g_trail_sl>0 ? g_trail_sl : g_sl_px, 2) + "\n";
      status += "TP2: " + DoubleToString(g_tp2_px, 2) + "\n";
   }
   Comment(status);
}
//+------------------------------------------------------------------+
