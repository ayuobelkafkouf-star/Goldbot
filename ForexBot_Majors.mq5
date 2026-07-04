//+------------------------------------------------------------------+
//|                                            ForexBot_Majors.mq5   |
//|          Strategia S/D multi-timeframe per EURUSD e GBPUSD       |
//|          Adattamento forex del motore GoldBot v5.2              |
//+------------------------------------------------------------------+
#property copyright "ForexBot Majors v1.0"
#property version   "1.00"
#property strict
#property description "ForexBot EURUSD/GBPUSD - Supply/Demand multi-zona, trend H1+M15, RSI, ATR, risk dinamico, trailing. Auto-adatta pip/spread al simbolo."

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
input int       InpMinScore    = 60;   // Score minimo per trade (Estesa = min 70)
input int       InpMaxZones    = 5;    // Zone attive max per lato

input group "═══ Trend ═══"
input int       InpH1Fast      = 21;   // H1 EMA veloce
input int       InpH1Slow      = 55;   // H1 EMA lenta
input int       InpM15Fast     = 21;   // M15 EMA veloce
input int       InpM15Slow     = 55;   // M15 EMA lenta

input group "═══ RSI ═══"
input int       InpRSILen      = 14;   // RSI periodo
input int       InpRSIOB       = 65;   // RSI ipercomprato
input int       InpRSIOS       = 35;   // RSI ipervenduto

input group "═══ Zone S/D ═══"
input int       InpPivotLeft   = 5;    // Pivot left bars
input int       InpPivotRight  = 3;    // Pivot right bars
input double    InpZoneWidth   = 1.5;  // Larghezza zona ATR
input double    InpZoneTol      = 0.5; // Tolleranza retest ATR

input group "═══ Spike + Conferma ═══"
input double    InpSpikeMult   = 0.5;  // Spike minimo ATR
input double    InpBodyMult    = 0.3;  // Body conferma minimo ATR

input group "═══ Rischio ═══"
input double    InpRiskPct     = 0.5;  // Rischio % per trade (0.5% x 2 pair = 1% tot)
input double    InpSLAtrMult   = 0.4;  // SL buffer ATR
input int       InpTP1Pct      = 70;   // % chiusura TP1
input bool      InpUseBE       = true; // Break-even dopo TP1
input bool      InpUseTrail    = true; // Trailing stop ATR dopo TP1
input double    InpTrailMult   = 1.5;  // Trailing ATR multiplier

input group "═══ Sessione (Europe/Rome) ═══"
input int       InpSessionStart= 13;   // Overlap London/NY start
input int       InpSessionEnd  = 17;   // Overlap London/NY end
input int       InpStartHour   = 9;    // Estesa/Aggressiva: ora inizio (London open)
input int       InpEndHour     = 20;   // Estesa/Aggressiva: ora fine

input group "═══ Protezione ═══"
input bool      InpUseCircuit  = true; // Circuit breaker drawdown
input double    InpDDThreshold = 5.0;  // DD max % dal peak
input int       InpPauseDays   = 3;    // Giorni pausa dopo trigger

input group "═══ Filtri Forex ═══"
input bool      InpUseATR      = true; // Filtro ATR minimo
input double    InpATRMinPips  = 4.0;  // ATR minimo in PIP (filtra fasi morte)
input bool      InpUseSpread   = true; // Filtro spread massimo
input double    InpMaxSpreadPips = 2.0;// Spread massimo in PIP per entrare
input int       InpCooldownBars= 5;    // Cooldown barre M15
input int       InpMaxTradesDay= 5;    // Max trade giorno
input double    InpMaxLoss     = 1.0;  // Max perdita % giorno
input double    InpMaxProfit   = 5.0;  // Max profitto % giorno

input group "═══ Notizie (Europe/Rome) ═══"
input bool      InpUseNews     = true; // Filtro notizie ad alto impatto
input bool      InpNews1Active = true; // Notizia 1 (NFP/CPI US)
input int       InpNews1Hour   = 14;   // Ora notizia 1
input int       InpNews1Min    = 30;   // Min notizia 1
input bool      InpNews2Active = false;// Notizia 2 (ECB/BoE)
input int       InpNews2Hour   = 14;
input int       InpNews2Min    = 15;
input bool      InpNews3Active = false;// Notizia 3 (FOMC)
input int       InpNews3Hour   = 20;
input int       InpNews3Min    = 0;
input int       InpNewsBefore  = 30;   // Minuti prima notizia
input int       InpNewsAfter   = 30;   // Minuti dopo notizia

input group "═══ Esecuzione ═══"
input ulong     InpMagic       = 20260704; // Magic Number
input int       InpSlippagePts = 20;   // Slippage in punti

//============================ GLOBALS ==============================
int h_h1_ef, h_h1_es;
int h_m15_ef, h_m15_es, h_m15_rsi, h_m15_atr;
int h_atr_local;

double  g_sup_tops[];
double  g_sup_bots[];
double  g_dem_tops[];
double  g_dem_bots[];

datetime g_last_m15_bar = 0;
datetime g_last_close_time = 0;
int      g_trades_today = 0;
int      g_last_day = -1;
int      g_day_counter = 0;
int      g_pause_until_d = 0;
double   g_eq_peak = 0;
double   g_day_eq = 0;

bool     g_be_active = false;
double   g_trail_sl  = 0;
double   g_entry_px  = 0;
double   g_tp1_px    = 0;
double   g_tp2_px    = 0;
double   g_sl_px     = 0;
bool     g_tp1_hit   = false;
bool     g_is_long   = false;

bool   g_eff_use_session;
bool   g_eff_force_hours;
int    g_eff_cooldown;
int    g_eff_max_trades;
double g_eff_zone_tol;
int    g_eff_min_score;

int    g_tz_offset_hours = 0;
double g_pip = 0;        // dimensione di 1 pip nel prezzo
int    g_price_digits = 5;

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

   // Pip forex: su quotazioni a 3/5 decimali 1 pip = 10 point, altrimenti 1 point
   g_price_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_pip = (g_price_digits == 3 || g_price_digits == 5) ? point * 10.0 : point;

   h_h1_ef    = iMA (_Symbol, PERIOD_H1,  InpH1Fast,  0, MODE_EMA, PRICE_CLOSE);
   h_h1_es    = iMA (_Symbol, PERIOD_H1,  InpH1Slow,  0, MODE_EMA, PRICE_CLOSE);
   h_m15_ef   = iMA (_Symbol, PERIOD_M15, InpM15Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_m15_es   = iMA (_Symbol, PERIOD_M15, InpM15Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_m15_rsi  = iRSI(_Symbol, PERIOD_M15, InpRSILen, PRICE_CLOSE);
   h_m15_atr  = iATR(_Symbol, PERIOD_M15, 14);
   h_atr_local= iATR(_Symbol, _Period,    14);

   if(h_h1_ef==INVALID_HANDLE || h_h1_es==INVALID_HANDLE ||
      h_m15_ef==INVALID_HANDLE|| h_m15_es==INVALID_HANDLE||
      h_m15_rsi==INVALID_HANDLE||h_m15_atr==INVALID_HANDLE||
      h_atr_local==INVALID_HANDLE)
   {
      Print("Errore creazione handles indicatori");
      return INIT_FAILED;
   }

   ArrayResize(g_sup_tops, 0);
   ArrayResize(g_sup_bots, 0);
   ArrayResize(g_dem_tops, 0);
   ArrayResize(g_dem_bots, 0);

   g_eq_peak = AccountInfoDouble(ACCOUNT_EQUITY);
   g_day_eq  = g_eq_peak;

   ApplyMode();
   ComputeTzOffset();

   Comment("ForexBot Majors v1.0 inizializzato — ", _Symbol, " — modalità: ", ModeName());
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(h_h1_ef);
   IndicatorRelease(h_h1_es);
   IndicatorRelease(h_m15_ef);
   IndicatorRelease(h_m15_es);
   IndicatorRelease(h_m15_rsi);
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
   g_eff_zone_tol    = is_aggr ? 0.7: InpZoneTol;
   g_eff_min_score   = is_ext  ? (int)MathMax(InpMinScore, 70) : InpMinScore;
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
//| Helper: copia 1 valore da buffer al bar idx                       |
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
//| Spread corrente in pip                                            |
//+------------------------------------------------------------------+
double CurrentSpreadPips()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(g_pip <= 0) return 0;
   return (ask - bid) / g_pip;
}

//+------------------------------------------------------------------+
//| Process new closed M15 bar                                        |
//+------------------------------------------------------------------+
void ProcessNewBar()
{
   double h1_ef, h1_es, m15_ef, m15_es, m15_rsi_v, m15_atr_v, atr_local;
   if(!GetBuf(h_h1_ef, 1, h1_ef))   return;
   if(!GetBuf(h_h1_es, 1, h1_es))   return;
   if(!GetBuf(h_m15_ef,1, m15_ef))  return;
   if(!GetBuf(h_m15_es,1, m15_es))  return;
   if(!GetBuf(h_m15_rsi,1,m15_rsi_v))return;
   if(!GetBuf(h_m15_atr,1,m15_atr_v))return;
   if(!GetBuf(h_atr_local,1,atr_local))return;

   double m15_o = iOpen (_Symbol, PERIOD_M15, 1);
   double m15_h = iHigh (_Symbol, PERIOD_M15, 1);
   double m15_l = iLow  (_Symbol, PERIOD_M15, 1);
   double m15_c = iClose(_Symbol, PERIOD_M15, 1);
   double m15_h_prev = iHigh(_Symbol, PERIOD_M15, 2);
   double m15_l_prev = iLow (_Symbol, PERIOD_M15, 2);

   bool h1_bull  = h1_ef > h1_es;
   bool h1_bear  = h1_ef < h1_es;
   bool m15_bull = m15_ef > m15_es;
   bool m15_bear = m15_ef < m15_es;

   double new_ph, new_pl;
   bool has_ph = DetectPivotHigh(m15_atr_v, new_ph);
   bool has_pl = DetectPivotLow (m15_atr_v, new_pl);

   if(has_ph) PushSupplyZone(new_ph, m15_atr_v);
   if(has_pl) PushDemandZone(new_pl, m15_atr_v);

   InvalidateZones(m15_c, m15_atr_v);

   bool price_at_supply = IsAtSupply(m15_h, m15_atr_v);
   bool price_at_demand = IsAtDemand(m15_l, m15_atr_v);

   bool spike_up   = (m15_h - m15_l) >= m15_atr_v * InpSpikeMult && m15_h > m15_h_prev;
   bool spike_down = (m15_h - m15_l) >= m15_atr_v * InpSpikeMult && m15_l < m15_l_prev;
   double body_sell = m15_o - m15_c;
   double body_buy  = m15_c - m15_o;
   bool confirm_sell = spike_up   && m15_c < m15_o && body_sell >= m15_atr_v * InpBodyMult;
   bool confirm_buy  = spike_down && m15_c > m15_o && body_buy  >= m15_atr_v * InpBodyMult;

   datetime now = TimeCurrent();
   int h_rome = RomeHour(now);
   int m_rome = RomeMinute(now);

   bool session_ok = (h_rome >= InpSessionStart && h_rome < InpSessionEnd);
   bool hours_ok   = (h_rome >= InpStartHour    && h_rome < InpEndHour);
   bool hour_ok    = g_eff_use_session ? session_ok : (g_eff_force_hours ? hours_ok : true);

   // Filtro ATR in pip (indipendente dal simbolo)
   double atr_pips = g_pip > 0 ? atr_local / g_pip : 0;
   bool atr_ok     = !InpUseATR || atr_pips >= InpATRMinPips;
   bool spread_ok  = !InpUseSpread || CurrentSpreadPips() <= InpMaxSpreadPips;

   bool rsi_ok_sell= m15_rsi_v > 45 && m15_rsi_v < InpRSIOB;
   bool rsi_ok_buy = m15_rsi_v < 55 && m15_rsi_v > InpRSIOS;
   bool news_ok    = !InpUseNews || !IsNewsTime(h_rome, m_rome);

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

   if(eq > g_eq_peak) g_eq_peak = eq;
   double dd_pct = g_eq_peak > 0 ? (g_eq_peak - eq) / g_eq_peak * 100.0 : 0;
   if(InpUseCircuit && dd_pct >= InpDDThreshold && g_day_counter >= g_pause_until_d)
      g_pause_until_d = g_day_counter + InpPauseDays;
   bool circuit_ok = !InpUseCircuit || g_day_counter >= g_pause_until_d;

   int score_sell = 0, score_buy = 0;
   if(h1_bear)         score_sell += 25;
   if(h1_bull)         score_buy  += 25;
   if(m15_bear)        score_sell += 20;
   if(m15_bull)        score_buy  += 20;
   if(price_at_supply) score_sell += 20;
   if(price_at_demand) score_buy  += 20;
   if(rsi_ok_sell)     score_sell += 15;
   if(rsi_ok_buy)      score_buy  += 15;
   long  v_arr[]; ArraySetAsSeries(v_arr, true);
   long  v_now=0, v_sma=0;
   if(CopyTickVolume(_Symbol, PERIOD_M15, 1, 21, v_arr) == 21)
   {
      v_now = v_arr[0];
      long sum=0; for(int i=1;i<=20;i++) sum += v_arr[i];
      v_sma = sum/20;
   }
   bool vol_high = (v_sma>0) && (v_now > v_sma * 1.2);
   if(vol_high)        { score_sell += 10; score_buy += 10; }
   if(atr_ok)          { score_sell += 10; score_buy += 10; }

   bool score_ok_sell = score_sell >= g_eff_min_score;
   bool score_ok_buy  = score_buy  >= g_eff_min_score;

   bool no_position = !HasOpenPosition();
   bool final_sell = confirm_sell && price_at_supply && h1_bear && m15_bear && rsi_ok_sell &&
                     hour_ok && atr_ok && spread_ok && news_ok && cooldown_ok && trades_ok &&
                     day_ok && circuit_ok && score_ok_sell && no_position;
   bool final_buy  = confirm_buy  && price_at_demand && h1_bull && m15_bull && rsi_ok_buy  &&
                     hour_ok && atr_ok && spread_ok && news_ok && cooldown_ok && trades_ok &&
                     day_ok && circuit_ok && score_ok_buy  && no_position;

   if(final_buy)  OpenLong (m15_l, m15_atr_v, atr_local);
   if(final_sell) OpenShort(m15_h, m15_atr_v, atr_local);
}

//+------------------------------------------------------------------+
//| Pivot detection                                                   |
//+------------------------------------------------------------------+
bool DetectPivotHigh(double atr_m15, double &out_value)
{
   int pivot_idx = InpPivotRight + 1;
   double phigh = iHigh(_Symbol, PERIOD_M15, pivot_idx);
   for(int i = 1; i <= pivot_idx + InpPivotLeft; i++)
   {
      if(i == pivot_idx) continue;
      double h = iHigh(_Symbol, PERIOD_M15, i);
      if(h >= phigh) return false;
   }
   out_value = phigh;
   return true;
}

bool DetectPivotLow(double atr_m15, double &out_value)
{
   int pivot_idx = InpPivotRight + 1;
   double plow = iLow(_Symbol, PERIOD_M15, pivot_idx);
   for(int i = 1; i <= pivot_idx + InpPivotLeft; i++)
   {
      if(i == pivot_idx) continue;
      double l = iLow(_Symbol, PERIOD_M15, i);
      if(l <= plow) return false;
   }
   out_value = plow;
   return true;
}

//+------------------------------------------------------------------+
//| Push/trim zone arrays                                             |
//+------------------------------------------------------------------+
void PushSupplyZone(double pivot_high, double atr_m15)
{
   double top = pivot_high;
   double bot = pivot_high - atr_m15 * InpZoneWidth;
   int sz = ArraySize(g_sup_tops);
   ArrayResize(g_sup_tops, sz+1);
   ArrayResize(g_sup_bots, sz+1);
   g_sup_tops[sz] = top;
   g_sup_bots[sz] = bot;
   while(ArraySize(g_sup_tops) > InpMaxZones)
   {
      ArrayRemoveAt(g_sup_tops, 0);
      ArrayRemoveAt(g_sup_bots, 0);
   }
}

void PushDemandZone(double pivot_low, double atr_m15)
{
   double bot = pivot_low;
   double top = pivot_low + atr_m15 * InpZoneWidth;
   int sz = ArraySize(g_dem_tops);
   ArrayResize(g_dem_tops, sz+1);
   ArrayResize(g_dem_bots, sz+1);
   g_dem_tops[sz] = top;
   g_dem_bots[sz] = bot;
   while(ArraySize(g_dem_tops) > InpMaxZones)
   {
      ArrayRemoveAt(g_dem_tops, 0);
      ArrayRemoveAt(g_dem_bots, 0);
   }
}

void ArrayRemoveAt(double &arr[], int idx)
{
   int n = ArraySize(arr);
   if(idx < 0 || idx >= n) return;
   for(int i = idx; i < n-1; i++) arr[i] = arr[i+1];
   ArrayResize(arr, n-1);
}

void InvalidateZones(double m15_close, double atr_m15)
{
   for(int i = ArraySize(g_sup_tops) - 1; i >= 0; i--)
      if(m15_close > g_sup_tops[i] + atr_m15 * 0.5)
      {
         ArrayRemoveAt(g_sup_tops, i);
         ArrayRemoveAt(g_sup_bots, i);
      }
   for(int i = ArraySize(g_dem_tops) - 1; i >= 0; i--)
      if(m15_close < g_dem_bots[i] - atr_m15 * 0.5)
      {
         ArrayRemoveAt(g_dem_tops, i);
         ArrayRemoveAt(g_dem_bots, i);
      }
}

bool IsAtSupply(double m15_high, double atr_m15)
{
   for(int i = 0; i < ArraySize(g_sup_tops); i++)
      if(m15_high >= g_sup_bots[i] - atr_m15 * g_eff_zone_tol &&
         m15_high <= g_sup_tops[i] + atr_m15 * g_eff_zone_tol)
         return true;
   return false;
}

bool IsAtDemand(double m15_low, double atr_m15)
{
   for(int i = 0; i < ArraySize(g_dem_tops); i++)
      if(m15_low <= g_dem_tops[i] + atr_m15 * g_eff_zone_tol &&
         m15_low >= g_dem_bots[i] - atr_m15 * g_eff_zone_tol)
         return true;
   return false;
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
//+------------------------------------------------------------------+
void OpenLong(double m15_low, double atr_m15, double atr_local)
{
   Sym.RefreshRates();
   double price = Sym.Ask();
   double sl    = m15_low - atr_local * InpSLAtrMult;
   double tp1 = iHigh(_Symbol, PERIOD_M15, iHighest(_Symbol, PERIOD_M15, MODE_HIGH, 20, 1));
   double tp2 = iHigh(_Symbol, PERIOD_H1,  iHighest(_Symbol, PERIOD_H1,  MODE_HIGH, 20, 1));
   if(tp1 <= price || tp2 <= tp1) return;

   double lots = CalculateLotSize(price - sl);
   if(lots <= 0) return;

   if(Trade.Buy(lots, _Symbol, price, sl, tp2, "ForexBot BUY"))
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

   if(Trade.Sell(lots, _Symbol, price, sl, tp2, "ForexBot SELL"))
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

   if(ptype == POSITION_TYPE_BUY)
   {
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
   int dgt = g_price_digits;

   string status = "";
   status += "═══ ForexBot Majors v1.0 ═══\n";
   status += "Simbolo: " + _Symbol + "  |  Modalità: " + ModeName() + "\n";
   status += "Equity: "   + DoubleToString(eq, 2) + "\n";
   status += "Spread: " + DoubleToString(CurrentSpreadPips(), 1) + " pip\n";
   status += "P&L oggi: " + DoubleToString(day_pct, 2) + "%\n";
   status += "Trade oggi: " + IntegerToString(g_trades_today) + "/" + IntegerToString(g_eff_max_trades) + "\n";
   status += "DD dal peak: " + DoubleToString(dd_pct, 2) + "%\n";
   status += "Status: " + (pause_left>0 ? ("PAUSED " + IntegerToString(pause_left) + "g") : "ACTIVE") + "\n";
   status += "Supply zones: " + IntegerToString(ArraySize(g_sup_tops)) + "\n";
   status += "Demand zones: " + IntegerToString(ArraySize(g_dem_tops)) + "\n";
   if(HasOpenPosition())
   {
      status += "Posizione: " + (g_is_long ? "LONG" : "SHORT");
      if(g_be_active) status += " (BE" + (InpUseTrail ? "+TRAIL" : "") + ")";
      status += "\n";
      status += "SL: " + DoubleToString(g_trail_sl>0 ? g_trail_sl : g_sl_px, dgt) + "\n";
      status += "TP2: " + DoubleToString(g_tp2_px, dgt) + "\n";
   }
   Comment(status);
}
//+------------------------------------------------------------------+
