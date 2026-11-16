-- ============================================================
-- Air Cargo Route Optimisation — key SQL queries (SQLite)
-- Dataset: 12,000 shipments, 8 Indian airports, 2024–2025
-- Unit economics: ton-km = distance_km * weight_kg / 1000
-- ============================================================

-- 1. Network KPIs
SELECT COUNT(*) shipments,
       SUM(revenue) revenue,
       SUM(total_cost) total_cost,
       SUM(profit) profit,
       ROUND(100.0*SUM(profit)/SUM(revenue),2) margin_pct,
       ROUND(SUM(total_cost)*1000.0/SUM(distance_km*weight_kg),2) cost_per_ton_km,
       ROUND(SUM(revenue)*1000.0/SUM(distance_km*weight_kg),2) rev_per_ton_km,
       ROUND(AVG(load_factor)*100,1) avg_load_factor
FROM shipments WHERE status='Delivered';

-- 2. Cost structure decomposition
SELECT SUM(fuel_cost) fuel, SUM(handling_cost) handling,
       SUM(crew_cost) crew, SUM(ground_cost) ground
FROM shipments WHERE status='Delivered';

-- 3. Route profitability — best and worst lanes (pooled profit)
SELECT origin || '→' || destination AS route,
       COUNT(*) shipments, SUM(revenue) revenue, SUM(profit) profit,
       ROUND(100.0*SUM(profit)/SUM(revenue),2) margin_pct,
       ROUND(AVG(load_factor)*100,1) avg_load_factor
FROM shipments WHERE status='Delivered'
GROUP BY route HAVING COUNT(*) >= 50
ORDER BY profit DESC;   -- flip to ASC for the worst routes

-- 4. Aircraft unit economics — cost per ton-km by fleet type
SELECT aircraft, COUNT(*) shipments,
       ROUND(SUM(total_cost)*1000.0/SUM(distance_km*weight_kg),2) cost_per_ton_km,
       ROUND(SUM(revenue)*1000.0/SUM(distance_km*weight_kg),2) rev_per_ton_km,
       ROUND(AVG(load_factor)*100,1) avg_load_factor,
       SUM(profit) profit
FROM shipments WHERE status='Delivered' GROUP BY aircraft;

-- 5. Load factor vs margin — the consolidation case
SELECT CASE WHEN load_factor < 0.60 THEN '<60%'
            WHEN load_factor < 0.75 THEN '60-75%'
            WHEN load_factor < 0.90 THEN '75-90%'
            ELSE '90%+' END AS load_band,
       COUNT(*) shipments, SUM(profit) profit,
       ROUND(100.0*SUM(profit)/SUM(revenue),2) margin_pct
FROM shipments WHERE status='Delivered' GROUP BY load_band ORDER BY load_band;

-- 6. Cargo type yield (revenue per ton-km)
SELECT cargo_type, COUNT(*) shipments, SUM(revenue) revenue, SUM(profit) profit,
       ROUND(100.0*SUM(profit)/SUM(revenue),2) margin_pct,
       ROUND(SUM(revenue)*1000.0/SUM(distance_km*weight_kg),2) rev_per_ton_km
FROM shipments WHERE status='Delivered' GROUP BY cargo_type ORDER BY revenue DESC;

-- 7. Monthly network profit trend
SELECT substr(date,1,7) AS ym, COUNT(*) shipments, SUM(revenue) revenue, SUM(profit) profit
FROM shipments WHERE status='Delivered' GROUP BY ym ORDER BY ym;

-- 8. Fuel cost share by aircraft (fuel burn differences)
SELECT aircraft,
       ROUND(100.0*SUM(fuel_cost)/SUM(total_cost),1) fuel_share_pct,
       ROUND(SUM(total_cost)*1000.0/SUM(distance_km*weight_kg),2) cost_per_ton_km
FROM shipments WHERE status='Delivered' GROUP BY aircraft;

-- 9. Lane-level unit economics with window ranking
WITH route_agg AS (
  SELECT origin, destination,
         COUNT(*) shipments,
         SUM(revenue) revenue, SUM(total_cost) cost, SUM(profit) profit,
         SUM(distance_km*weight_kg) ton_km
  FROM shipments WHERE status='Delivered'
  GROUP BY origin, destination HAVING COUNT(*) >= 50
)
SELECT origin || '→' || destination AS route, shipments,
       ROUND(revenue*1000.0/ton_km,2) rev_per_ton_km,
       ROUND(cost*1000.0/ton_km,2) cost_per_ton_km,
       ROUND(100.0*profit/revenue,2) margin_pct,
       DENSE_RANK() OVER (ORDER BY profit DESC) profit_rank
FROM route_agg;

-- 10. Reliability: on-time performance by route
SELECT origin || '→' || destination AS route,
       COUNT(*) shipments,
       ROUND(100.0*SUM(CASE WHEN status='Delivered' THEN 1 ELSE 0 END)/COUNT(*),1) on_time_pct,
       ROUND(100.0*SUM(CASE WHEN status='Delayed' THEN 1 ELSE 0 END)/COUNT(*),1) delayed_pct
FROM shipments GROUP BY route ORDER BY delayed_pct DESC LIMIT 10;
