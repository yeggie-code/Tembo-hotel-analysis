select * from tembo_hotel.staging_tembo;
---===================================================================
--=========================LOADING AND ANALYSING THE DATA======================
DROP TABLE IF EXISTS tembo_views;


---=====================CREATING A LANDING TABLE============================
CREATE TABLE IF NOT EXISTS tembo_views (
    booking_id       VARCHAR(10) PRIMARY KEY,
    guest_name        VARCHAR(100),
    guest_phone       VARCHAR(15),
    guest_city        VARCHAR(60),
    guest_nationality VARCHAR(60),
    room_no           VARCHAR(10),
    room_type         VARCHAR(20),
    room_rate         NUMERIC(10,2),
    check_in_date     DATE,
    check_out_date    DATE,
    nights_stayed     INTEGER,
    staff_name        VARCHAR(100),
    staff_department  VARCHAR(30),
    staff_salary      NUMERIC(12,2),
    payment_method    VARCHAR(20),
    booking_status    VARCHAR(20),
    total_bill        NUMERIC(12,2),
    extra_service     VARCHAR(40),
    extra_service_cost NUMERIC(10,2),
    guest_rating      INTEGER
);

--=================LOADING THE DATA========================
INSERT INTO tembo_views
SELECT DISTINCT ON (booking_id)
    booking_id,
    TRIM(guest_name),
    NULLIF(TRIM(guest_phone), ''),
    COALESCE(NULLIF(TRIM(guest_city), ''), 'Unknown'),
    TRIM(guest_nationality),
    TRIM(room_no),
    INITCAP(TRIM(room_type)),
    NULLIF(REGEXP_REPLACE(guest_rating, '[^0-9.]', '', 'g'), '')::NUMERIC,
    check_in_date::DATE,
    check_out_date::DATE,
    (check_out_date::DATE - check_in_date::DATE),
    TRIM(staff_name),
    INITCAP(TRIM(staff_department)),
    NULLIF(REGEXP_REPLACE(staff_salary, '[^0-9.]', '', 'g'), '')::NUMERIC,
    CASE
        WHEN INITCAP(TRIM(payment_method)) IN ('Mpesa', 'M-Pesa', 'M Pesa') THEN 'M-Pesa'
        ELSE INITCAP(TRIM(payment_method))
    END,
    TRIM(booking_status),
    NULLIF(REGEXP_REPLACE(total_amount, '[^0-9.]', '', 'g'), '')::NUMERIC,
    NULLIF(TRIM(service_used), ''),
    NULLIF(REGEXP_REPLACE(service_price, '[^0-9.]', '', 'g'), '')::NUMERIC,
    NULLIF(REGEXP_REPLACE(guest_rating, '[^0-9]', '', 'g'), '')::INTEGER
from tembo_hotel.staging_tembo
WHERE check_in_date SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}'
  AND check_out_date SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}'
  AND check_out_date::DATE > check_in_date::DATE
ORDER BY booking_id, check_in_date;









-- ==============================================================================
-- ===============  TEMBO HOTEL — CLEAN LOAD (staging -> production)  ============
-- ==============================================================================
set search_path to tembo_hotel;

-- quick look at raw staging
-- SELECT * FROM tembo_hotel.staging_tembo;

-- ------------------------------------------------------------------------------
-- 1. PRODUCTION TABLE  (clean, typed, deduped)
--    CASCADE so re-runs don't fail once views are built on top of it.
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS tembo_hotel.tembo_bookings;

CREATE TABLE tembo_hotel.tembo_bookings (
    booking_id         VARCHAR(10) PRIMARY KEY,
    guest_name         VARCHAR(100),
    guest_phone        VARCHAR(15),
    guest_city         VARCHAR(60),
    guest_nationality  VARCHAR(60),
    room_no            VARCHAR(10),
    room_type          VARCHAR(20),
    room_rate          NUMERIC(10,2),
    check_in_date      DATE,
    check_out_date     DATE,
    nights_stayed      INTEGER,        -- derived from the dates, not trusted from staging
    staff_name         VARCHAR(100),
    staff_department   VARCHAR(30),
    staff_salary       NUMERIC(12,2),
    payment_method     VARCHAR(20),
    booking_status     VARCHAR(20),
    total_bill         NUMERIC(12,2),
    extra_service      VARCHAR(40),
    extra_service_cost NUMERIC(10,2),
    guest_rating       INTEGER
);

-- ------------------------------------------------------------------------------
-- 2. CLEAN + LOAD
--    Cleaning happens in the CTE, then the INSERT dedupes and rebuilds totals.
-- ------------------------------------------------------------------------------
WITH parsed AS (
    SELECT
        TRIM(booking_id)                                              AS booking_id,
        TRIM(guest_name)                                             AS guest_name,
        NULLIF(TRIM(guest_phone), '')                               AS guest_phone,
        COALESCE(NULLIF(TRIM(guest_city), ''), 'Unknown')           AS guest_city,
        COALESCE(NULLIF(TRIM(guest_nationality), ''), 'Unknown')     AS guest_nationality,
        TRIM(room_no)                                               AS room_no,
        INITCAP(TRIM(room_type))                                    AS room_type,
        -- >>> CHECK THIS: staging's nightly-rate column. Rename if it isn't room_rate.
        NULLIF(REGEXP_REPLACE(guest_rating, '[^0-9.]', '', 'g'), '')::NUMERIC AS room_rate,
        check_in_date::DATE                                          AS check_in_date,
        check_out_date::DATE                                         AS check_out_date,
        TRIM(staff_name)                                            AS staff_name,
        INITCAP(TRIM(staff_department))                             AS staff_department,
        NULLIF(REGEXP_REPLACE(staff_salary, '[^0-9.]', '', 'g'), '')::NUMERIC AS staff_salary,
        CASE                                                        -- collapse Mpesa / M-Pesa / M Pesa
            WHEN LOWER(REPLACE(REPLACE(TRIM(payment_method), '-', ''), ' ', '')) = 'mpesa'
                 THEN 'M-Pesa'
            ELSE INITCAP(TRIM(payment_method))
        END                                                         AS payment_method,
        TRIM(booking_status)                                       AS booking_status,
        NULLIF(REGEXP_REPLACE(total_amount, '[^0-9.]', '', 'g'), '')::NUMERIC AS total_amount,
        NULLIF(TRIM(service_used), '')                             AS extra_service,
        NULLIF(REGEXP_REPLACE(service_price, '[^0-9.]', '', 'g'), '')::NUMERIC AS extra_service_cost,
        CASE                                                        -- keep only valid 1..5 ratings
            WHEN NULLIF(REGEXP_REPLACE(guest_rating, '[^0-9]', '', 'g'), '')::INTEGER BETWEEN 1 AND 5
                 THEN NULLIF(REGEXP_REPLACE(guest_rating, '[^0-9]', '', 'g'), '')::INTEGER
        END                                                         AS guest_rating
    FROM tembo_hotel.staging_tembo
    WHERE check_in_date  SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}'
      AND check_out_date SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}'
      AND check_out_date::DATE > check_in_date::DATE                -- drop reversed-date rows
)
INSERT INTO tembo_hotel.tembo_bookings
SELECT DISTINCT ON (booking_id)
    booking_id,
    guest_name,
    guest_phone,
    guest_city,
    guest_nationality,
    room_no,
    room_type,
    room_rate,
    check_in_date,
    check_out_date,
    (check_out_date - check_in_date)                                AS nights_stayed,
    staff_name,
    staff_department,
    staff_salary,
    payment_method,
    booking_status,
    COALESCE(                                                       -- rebuild missing totals
        total_amount,
        room_rate * (check_out_date - check_in_date) + COALESCE(extra_service_cost, 0)
    )                                                              AS total_bill,
    extra_service,
    extra_service_cost,
    guest_rating
FROM parsed
ORDER BY booking_id, check_in_date                                 -- DISTINCT ON keeps first
ON CONFLICT (booking_id) DO NOTHING;                               -- safe on re-runs

-- ------------------------------------------------------------------------------
-- 3. VERIFY THE LOAD  (run these; don't just trust it worked)
-- ------------------------------------------------------------------------------
-- row count + sanity totals
SELECT COUNT(*) AS rows_loaded,
       COUNT(*) FILTER (WHERE total_bill  IS NULL) AS missing_total,
       COUNT(*) FILTER (WHERE guest_rating IS NULL) AS missing_or_invalid_rating,
       COUNT(*) FILTER (WHERE room_rate   IS NULL) AS missing_rate
FROM   tembo_hotel.tembo_bookings;

-- rows staging rejected (reversed / non-standard dates) — review, don't discard
SELECT booking_id, guest_name, check_in_date, check_out_date
FROM   tembo_hotel.staging_tembo
WHERE  NOT (check_out_date::DATE > check_in_date::DATE);

-- integrity: recorded nights vs actual date span (expect the long-stay anomalies)
SELECT booking_id, check_in_date, check_out_date, nights_stayed
FROM   tembo_hotel.tembo_bookings
WHERE  nights_stayed <> (check_out_date - check_in_date);          -- should return 0 rows now








-- ==============================================================================
-- ============  HOTEL BOOKINGS — BUSINESS ANALYSIS QUESTION BANK  ===============
-- ==============================================================================
-- Same analytical skeleton as your safari_connect script, mapped to hotel data.
-- Runs against hotel_ops.bookings (your cleaned production table).
-- Cross-refs like "(cf. safari 3A)" point to the pattern you already wrote.
-- ==============================================================================

set search_path to hotel_ops;

-- ------------------------------------------------------------------------------
-- STEP 0: the analysis view (your v_trips equivalent). Build this first.
-- Derives the date parts every trend query needs.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_stays AS
SELECT
    t.*,
    TO_CHAR(check_in_date, 'YYYY-MM')        AS check_in_month,
    TRIM(TO_CHAR(check_in_date, 'Day'))      AS check_in_day,
    EXTRACT(YEAR    FROM check_in_date)::int AS booking_year,
    EXTRACT(QUARTER FROM check_in_date)::int AS booking_quarter,
    (booking_status = 'Checked Out')         AS is_realised
FROM public.tembo_views t;


-- ==============================================================================
-- 1. ROOM & ROOM-TYPE ANALYSIS            (≈ safari Route Analysis)
-- ==============================================================================
/* Q1a - Which room types earn the most revenue? */
SELECT room_type, SUM(total_bill) AS total_revenue, SUM(nights_stayed) AS room_nights
FROM   v_stays WHERE is_realised
GROUP  BY room_type ORDER BY total_revenue DESC;

/* Q1b - Which are most popular?  (bookings vs room-nights tell different stories) */
SELECT room_type, COUNT(*) AS bookings, SUM(nights_stayed) AS room_nights
FROM   v_stays WHERE is_realised
GROUP  BY room_type ORDER BY bookings DESC;

/* Q1c - Most efficient per room-night sold?  ADR = revenue / nights  (cf. safari 1C revenue_per_seat) */
SELECT room_type,
       SUM(nights_stayed)                          AS room_nights,
       SUM(total_bill)                    AS revenue,
       ROUND(SUM(total_bill)/SUM(nights_stayed)) AS adr_per_room_night
FROM   v_stays WHERE is_realised
GROUP  BY room_type ORDER BY adr_per_room_night DESC;

/* Q1d - Room-type scorecard: which type is actually most profitable to run? */
SELECT room_type,
       COUNT(*)                   AS bookings,
       SUM(nights_stayed)                AS room_nights,
       ROUND(AVG(nights_stayed),1)       AS avg_length_of_stay,
       SUM(total_bill)          AS revenue,
       ROUND(AVG(guest_rating),2)       AS avg_rating
FROM   v_stays WHERE is_realised
GROUP  BY room_type ORDER BY revenue DESC;


-- ==============================================================================
-- 2. STAFF & DEPARTMENT THROUGHPUT        (≈ safari Driver Performance)
----===============================================================================
/* Q2a - Staff summary: bookings processed, revenue handled, avg guest rating */
SELECT staff_name, staff_department,
       COUNT(*)                AS bookings_processed,
       SUM(total_bill)       AS revenue_handled,
       ROUND(AVG(guest_rating),2)    AS avg_guest_rating
FROM   v_stays
GROUP  BY staff_name, staff_department ORDER BY revenue_handled DESC;

/* Q2b - Rank staff overall AND within department   */
WITH staff_totals AS (
    SELECT staff_name, staff_department,
           COUNT(*)          AS bookings_processed,
           SUM(total_bill) AS revenue_handled
    FROM   v_stays GROUP BY staff_name, staff_department
)
SELECT staff_name, staff_department, bookings_processed, revenue_handled,
       RANK() OVER (ORDER BY revenue_handled DESC)                          AS overall_rank,
       RANK() OVER (PARTITION BY staff_department ORDER BY revenue_handled DESC)  AS dept_rank
FROM   staff_totals ORDER BY overall_rank;

/* Q2c - Is booking volume evenly spread across departments?*/
SELECT staff_department, COUNT(*) AS bookings,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct_of_all_bookings
FROM   v_stays GROUP BY staff_department ORDER BY bookings DESC;


-- ==============================================================================
-- 3. REVENUE TRENDS                       
-- ==============================================================================
/* Q3a - Monthly revenue + month-over-month change */
WITH monthly AS (
    SELECT check_in_month, SUM(total_bill) AS revenue
    FROM   v_stays WHERE is_realised GROUP BY check_in_month
)
SELECT check_in_month, revenue,
       LAG(revenue) OVER (ORDER BY check_in_month)              AS prev_month,
       revenue - LAG(revenue) OVER (ORDER BY check_in_month)    AS change
FROM   monthly ORDER BY check_in_month;

/* Q3b - Running cumulative revenue */
WITH monthly AS (
    SELECT check_in_month, SUM(total_bill) AS revenue
    FROM   v_stays WHERE is_realised GROUP BY check_in_month
)
SELECT check_in_month, revenue,
       SUM(revenue) OVER (ORDER BY check_in_month) AS running_total
FROM   monthly ORDER BY check_in_month;

/* Q3c - Best & worst 3 months by revenue */
WITH monthly AS (
    SELECT check_in_month, SUM(total_bill) AS revenue
    FROM   v_stays WHERE is_realised GROUP BY check_in_month
),
ranked AS (
    SELECT check_in_month, revenue,
           RANK() OVER (ORDER BY revenue DESC) AS best_rank,
           RANK() OVER (ORDER BY revenue ASC)  AS worst_rank
    FROM monthly
)
SELECT * FROM ranked WHERE best_rank <= 3 OR worst_rank <= 3 ORDER BY revenue DESC;

/* Q3d - Revenue by room type per month — PIVOT */
SELECT check_in_month,
       SUM(CASE WHEN room_type='Standard'  THEN total_bill ELSE 0 END) AS standard,
       SUM(CASE WHEN room_type='Deluxe'    THEN total_bill ELSE 0 END) AS deluxe,
       SUM(CASE WHEN room_type='Suite'     THEN total_bill ELSE 0 END) AS suite,
       SUM(CASE WHEN room_type='Penthouse' THEN total_bill ELSE 0 END) AS penthouse
FROM   v_stays WHERE is_realised
GROUP  BY check_in_month ORDER BY check_in_month;

/* Q3e - BONUS (you have 2 years): 2023 vs 2024 same-month comparison */
SELECT TO_CHAR(check_in_date,'MM') AS month_no,
       SUM(total_bill) FILTER (WHERE booking_year=2023) AS rev_2023,
       SUM(total_bill) FILTER (WHERE booking_year=2024) AS rev_2024
FROM   v_stays WHERE is_realised
GROUP  BY 1 ORDER BY 1;


-- ==============================================================================
-- 4. GUEST INSIGHTS                        (≈ safari Passenger Insights)
-- ==============================================================================
/* Q4a - Top guest cities (only cities with 3+ bookings)  (cf. safari 4A: HAVING) */
SELECT guest_city,
       COUNT(*)                 AS total_bookings,
       SUM(nights_stayed)              AS total_room_nights,
       SUM(total_bill)        AS total_revenue,
       ROUND(AVG(total_bill)) AS avg_spend
FROM   v_stays WHERE is_realised
GROUP  BY guest_city HAVING COUNT(*) >= 3 ORDER BY total_bookings DESC;

/* Q4b - Repeat vs one-time guests, and how much revenue repeaters drive */
WITH per_guest AS (
    SELECT guest_name, COUNT(*) AS stays, SUM(total_bill) AS spend
    FROM   v_stays WHERE is_realised GROUP BY guest_name
)
SELECT CASE WHEN stays > 1 THEN 'Repeat' ELSE 'One-time' END AS guest_type,
       COUNT(*) AS guests, SUM(spend) AS revenue,
       ROUND(100.0*SUM(spend)/SUM(SUM(spend)) OVER (),1) AS pct_revenue
FROM   per_guest GROUP BY 1;

/* Q4c - Satisfaction breakdown with %  (cf. safari 4C: CTE) */
WITH cats AS (
    SELECT booking_id,
        CASE WHEN guest_rating IS NULL THEN 'No Rating'
             WHEN guest_rating >= 4    THEN 'Satisfied'
             WHEN guest_rating  = 3    THEN 'Neutral'
             ELSE 'Unsatisfied' END AS satisfaction
    FROM v_stays WHERE is_realised
)
SELECT satisfaction, COUNT(*) AS trips,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct
FROM   cats GROUP BY satisfaction ORDER BY trips DESC;

/* Q4d - Guest spend quartiles  (cf. safari 4D: NTILE, 'Top Spender') */
WITH spend AS (
    SELECT guest_name, SUM(total_bill) AS total_spent
    FROM   v_stays WHERE is_realised GROUP BY guest_name
),
q AS (SELECT guest_name, total_spent, NTILE(4) OVER (ORDER BY total_spent) AS quartile FROM spend)
SELECT guest_name, total_spent,
       CASE WHEN quartile = 4 THEN 'Top Spender' ELSE 'Quartile '||quartile END AS tier
FROM   q ORDER BY total_spent DESC;


-- ==============================================================================
-- 5. CANCELLATIONS & LOST REVENUE        
-- ==============================================================================
/* Q5a - Status breakdown with %  */
SELECT booking_status, COUNT(*) AS bookings,
       SUM(total_bill) AS revenue,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct_of_bookings
FROM   v_stays GROUP BY booking_status ORDER BY bookings DESC;

/* Q5b - Cancellation + no-show rate BY ROOM TYPE */
SELECT room_type,
       COUNT(*) AS total_bookings,
       SUM(CASE WHEN booking_status='Checked Out' THEN 1 ELSE 0 END) AS checked_out,
       SUM(CASE WHEN booking_status='Cancelled'   THEN 1 ELSE 0 END) AS cancelled,
       SUM(CASE WHEN booking_status='No Show'      THEN 1 ELSE 0 END) AS no_show,
       ROUND(100.0*SUM(CASE WHEN booking_status IN ('Cancelled','No Show') THEN 1 ELSE 0 END)
             / COUNT(*),1) AS lost_pct
FROM   v_stays GROUP BY room_type ORDER BY lost_pct DESC;

/* Q5c - Revenue lost to cancellations & no-shows */
SELECT booking_status, SUM(total_bill) AS lost_revenue
FROM   v_stays WHERE booking_status IN ('Cancelled','No Show')
GROUP  BY booking_status;

/* Q5d - Which guests cancel / no-show most? (retention risk) */
SELECT guest_name,
       COUNT(*) FILTER (WHERE booking_status IN ('Cancelled','No Show')) AS bad_bookings,
       COUNT(*) AS total_bookings
FROM   v_stays GROUP BY guest_name
HAVING COUNT(*) FILTER (WHERE booking_status IN ('Cancelled','No Show')) > 0
ORDER  BY bad_bookings DESC;


-- ==============================================================================
-- 6. STAY & OPERATIONAL PATTERNS          
-- ==============================================================================
/* Q6a - Revenue & arrivals by check-in day of week   */
SELECT check_in_day, COUNT(*) AS arrivals, SUM(total_bill) AS revenue
FROM   v_stays WHERE is_realised
GROUP  BY check_in_day ORDER BY revenue DESC;

/* Q6b - Length-of-stay bands: how many short vs long stays, and revenue each */
SELECT CASE WHEN nights_stayed = 1 THEN '1 night'
            WHEN nights_stayed BETWEEN 2 AND 3 THEN '2-3 nights'
            ELSE '4+ nights' END AS los_band,
       COUNT(*) AS bookings, SUM(total_bill) AS revenue
FROM   v_stays WHERE is_realised
GROUP  BY 1 ORDER BY revenue DESC;

/* Q6c - Seasonal load label per month  (cf. safari 6C seat-utilisation labels) */
WITH monthly AS (
    SELECT check_in_month, COUNT(*) AS bookings
    FROM v_stays WHERE is_realised GROUP BY check_in_month
)
SELECT check_in_month, bookings,
       CASE WHEN bookings >= 15 THEN 'Peak'
            WHEN bookings >= 8  THEN 'Steady'
            ELSE 'Quiet' END AS load_label
FROM   monthly ORDER BY bookings DESC;


-- ==============================================================================
-- 7. ANCILLARY / EXTRA SERVICES           
-- ==============================================================================
/* Q7a - Attach rate: what share of stays buy an extra service? */
SELECT ROUND(100.0*COUNT(*) FILTER (WHERE extra_service IS NOT NULL)/COUNT(*),1) AS attach_rate_pct
FROM   v_stays;

/* Q7b - Revenue per service vs how often it sells (earns-most vs sells-most) */
SELECT extra_service, COUNT(*) AS times_sold, SUM(extra_service_cost) AS revenue
FROM   v_stays WHERE extra_service IS NOT NULL
GROUP  BY extra_service ORDER BY revenue DESC;

/* Q7c - Which room types buy which services? (cross-sell pivot) */
SELECT room_type,
       COUNT(*) FILTER (WHERE extra_service = 'Spa Treatment')   AS spa,
       COUNT(*) FILTER (WHERE extra_service = 'Conference Room') AS conference,
       COUNT(*) FILTER (WHERE extra_service = 'Airport Pickup')  AS airport
FROM   v_stays GROUP BY room_type ORDER BY room_type;

/* Q7d - Do add-on buyers rate higher / stay longer? */
SELECT CASE WHEN extra_service IS NULL THEN 'No add-on' ELSE 'Bought add-on' END AS grp,
       ROUND(AVG(guest_rating),2) AS avg_rating, ROUND(AVG(nights_stayed),1) AS avg_nights
FROM   v_stays WHERE is_realised GROUP BY 1;

.

















-- ==============================================================================
-- ===============  TEMBO HOTEL — VIEWS LAYER (hand-off to BI)  ==================
-- ==============================================================================
-- Design: v_stays is the ONE fact view (one row per booking, cleaned+enriched).
-- Every reporting view below reads from v_stays, never from the base table.
-- So the base-table name is written exactly once — in v_stays. Change it there
-- only, and the whole layer follows.
-- ==============================================================================
set search_path to tembo_hotel;

-- ------------------------------------------------------------------------------
-- 0. FACT VIEW  — the star of the hand-off. A BI dev can build almost everything
--    from this alone: it's booking-grain, clean, with date parts pre-derived.
--    >>> The ONLY reference to the base table. If yours is still called
--        tembo_views, change tembo_bookings below to tembo_views.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_stays AS
SELECT
    t.*,
    TO_CHAR(check_in_date, 'YYYY-MM')         AS check_in_month,
    TRIM(TO_CHAR(check_in_date, 'Day'))       AS check_in_day,
    EXTRACT(YEAR    FROM check_in_date)::int  AS booking_year,
    EXTRACT(QUARTER FROM check_in_date)::int  AS booking_quarter,
    (booking_status = 'Checked Out')          AS is_realised
FROM tembo_hotel.tembo_bookings t;            -- <<< base table name lives here only

-- ------------------------------------------------------------------------------
-- 1. v_room_performance — revenue, occupancy and rating by room type
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_room_performance AS
SELECT
    room_type,
    COUNT(*)                                            AS bookings,
    SUM(nights_stayed)                                  AS room_nights,
    ROUND(AVG(nights_stayed), 1)                        AS avg_length_of_stay,
    SUM(total_bill)                                     AS revenue,
    ROUND(SUM(total_bill) / NULLIF(SUM(nights_stayed),0)) AS adr,       -- avg daily rate
    ROUND(AVG(guest_rating), 2)                         AS avg_rating
FROM tembo_hotel.v_stays
WHERE is_realised
GROUP BY room_type;

-- ------------------------------------------------------------------------------
-- 2. v_staff_workload — throughput per staff member (workload, NOT satisfaction)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_staff_workload AS
SELECT
    staff_name,
    staff_department,
    COUNT(*)                    AS bookings_processed,
    SUM(total_bill)             AS revenue_handled,
    ROUND(AVG(guest_rating), 2) AS avg_guest_rating
FROM tembo_hotel.v_stays
GROUP BY staff_name, staff_department;

-- ------------------------------------------------------------------------------
-- 3. v_monthly_revenue — revenue trend with month-over-month change (LAG)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_monthly_revenue AS
WITH m AS (
    SELECT check_in_month,
           SUM(total_bill)    AS revenue,
           SUM(nights_stayed) AS room_nights,
           COUNT(*)           AS bookings
    FROM tembo_hotel.v_stays
    WHERE is_realised
    GROUP BY check_in_month
)
SELECT
    check_in_month,
    revenue,
    room_nights,
    bookings,
    LAG(revenue) OVER (ORDER BY check_in_month)           AS prev_month,
    revenue - LAG(revenue) OVER (ORDER BY check_in_month) AS mom_change
FROM m;

-- ------------------------------------------------------------------------------
-- 4. v_monthly_room_revenue — TIDY month x room_type (let the BI tool pivot it)
--    Hand BI devs long/tidy data, not pre-pivoted columns — it's far more flexible.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_monthly_room_revenue AS
SELECT check_in_month, room_type,
       SUM(total_bill) AS revenue,
       COUNT(*)        AS bookings
FROM tembo_hotel.v_stays
WHERE is_realised
GROUP BY check_in_month, room_type;

-- ------------------------------------------------------------------------------
-- 5. v_cancellation_analysis — loss rate & lost revenue by room type
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_cancellation_analysis AS
SELECT
    room_type,
    COUNT(*)                                                       AS total_bookings,
    COUNT(*) FILTER (WHERE booking_status = 'Checked Out')         AS checked_out,
    COUNT(*) FILTER (WHERE booking_status = 'Cancelled')           AS cancelled,
    COUNT(*) FILTER (WHERE booking_status = 'No Show')             AS no_show,
    ROUND(100.0 * COUNT(*) FILTER (WHERE booking_status IN ('Cancelled','No Show'))
          / COUNT(*), 1)                                          AS lost_pct,
    SUM(total_bill) FILTER (WHERE booking_status IN ('Cancelled','No Show')) AS lost_revenue
FROM tembo_hotel.v_stays
GROUP BY room_type;

-- ------------------------------------------------------------------------------
-- 6. v_guest_insights — city-level demand (only cities with 3+ bookings)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_guest_insights AS
SELECT
    guest_city,
    COUNT(*)               AS total_bookings,
    SUM(nights_stayed)     AS room_nights,
    SUM(total_bill)        AS revenue,
    ROUND(AVG(total_bill)) AS avg_spend
FROM tembo_hotel.v_stays
WHERE is_realised
GROUP BY guest_city
HAVING COUNT(*) >= 3;

-- ------------------------------------------------------------------------------
-- 7. v_guest_value — one row per guest: frequency, spend, loyalty flag
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_guest_value AS
SELECT
    guest_name,
    COUNT(*)                    AS stays,
    SUM(nights_stayed)          AS total_nights,
    SUM(total_bill)             AS total_spend,
    ROUND(AVG(guest_rating), 2) AS avg_rating,
    (COUNT(*) > 1)              AS is_repeat_guest
FROM tembo_hotel.v_stays
WHERE is_realised
GROUP BY guest_name;

-- ------------------------------------------------------------------------------
-- 8. v_satisfaction_breakdown — rating buckets with share of total
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_satisfaction_breakdown AS
SELECT
    CASE WHEN guest_rating IS NULL THEN 'No Rating'
         WHEN guest_rating >= 4    THEN 'Satisfied'
         WHEN guest_rating  = 3    THEN 'Neutral'
         ELSE 'Unsatisfied' END                          AS satisfaction,
    COUNT(*)                                              AS bookings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS pct
FROM tembo_hotel.v_stays
WHERE is_realised
GROUP BY 1;

-- ------------------------------------------------------------------------------
-- 9. v_ancillary_performance — extra-service revenue vs frequency
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_ancillary_performance AS
SELECT
    extra_service,
    COUNT(*)                       AS times_sold,
    SUM(extra_service_cost)        AS revenue,
    ROUND(AVG(extra_service_cost)) AS avg_price
FROM tembo_hotel.v_stays
WHERE extra_service IS NOT NULL
GROUP BY extra_service;

-- ------------------------------------------------------------------------------
-- 10. v_payment_mix — tender split (useful for finance/reconciliation tiles)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW tembo_hotel.v_payment_mix AS
SELECT
    payment_method,
    COUNT(*)                                          AS txns,
    SUM(total_bill)                                   AS revenue,
    ROUND(100.0 * SUM(total_bill) / SUM(SUM(total_bill)) OVER (), 1) AS revenue_pct
FROM tembo_hotel.v_stays
WHERE is_realised
GROUP BY payment_method;

-- ==============================================================================
-- CHECK THE LAYER — every view should return rows
-- ==============================================================================
-- SELECT * FROM tembo_hotel.v_stays LIMIT 20;
-- SELECT * FROM tembo_hotel.v_room_performance    ORDER BY revenue DESC;
-- SELECT * FROM tembo_hotel.v_monthly_revenue     ORDER BY check_in_month;
-- SELECT * FROM tembo_hotel.v_cancellation_analysis ORDER BY lost_pct DESC;
-- SELECT * FROM tembo_hotel.v_guest_insights      ORDER BY total_bookings DESC;
-- SELECT * FROM tembo_hotel.v_satisfaction_breakdown;
-- SELECT * FROM tembo_hotel.v_ancillary_performance ORDER BY revenue DESC;

-- list everything you're handing over
SELECT table_name
FROM   information_schema.views
WHERE  table_schema = 'tembo_hotel'
ORDER  BY table_name;