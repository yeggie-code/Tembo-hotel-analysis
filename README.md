# Tembo-hotel-analysis
# Tembo Hotel — Bookings Analytics (SQL → BI)

An end-to-end analytics project on a hotel bookings dataset: raw data is
cleaned and modelled in **PostgreSQL**, exposed through a layer of analysis
**views**, and visualised in an interactive **Power BI** dashboard.

Built as a self-directed project to practise the full workflow a data analyst
runs — staging, cleaning, modelling, a views layer for hand-off, and a
business-facing dashboard.

---

## What's in here

| File | What it is |
|------|------------|
| `tembo_clean_load.sql` | Staging → production load: cleans, de-duplicates and type-casts the raw bookings into `tembo_bookings`. |
| `tembo_views_layer.sql` | The analysis views (`v_stays` + reporting marts) handed off to BI, plus the read-only `bi_reader` role. |
| `tembo_analysis_questions.sql` | The business questions, written as runnable SQL — the analytical framework behind the dashboard. |
| `tembo_dashboard.png` | Screenshot of the final Power BI dashboard. |

---

## The data

~200 hotel bookings across 2023–2024: guest, room, stay dates, staff,
payment, booking status, extra services and guest ratings.

Cleaning handled: duplicate booking IDs, reversed check-in/check-out dates,
mismatched night counts, inconsistent payment labels (`Mpesa` / `M-Pesa`),
missing totals (rebuilt from rate × nights + extras), out-of-range ratings
(kept only 1–5), and blank cities.

> Note: this is a **practice dataset** (21 distinct guests, masked phone
> numbers). It demonstrates the pipeline and BI skills, not real market findings.

---

## Pipeline

```
staging_tembo  ──clean/dedupe/validate──►  tembo_bookings  ──►  v_stays  ──►  v_* reporting views  ──►  Power BI
   (raw text)          (production)          (fact view)        (marts)         (dashboard)
```

Design choice: every reporting view reads from `v_stays`, and `v_stays` is the
only object that names the base table — so a rename touches exactly one line.

---

## The dashboard

Built entirely from the `v_stays` fact view so a single slicer filters the whole
page. It answers:

- **Revenue** — total, monthly trend, and average daily rate (ADR)
- **Room mix** — which room types earn most vs get booked most
- **Revenue leakage** — cancellation / no-show rate and lost revenue by room type
- **Guest satisfaction** — rating breakdown with semantic (green→amber→red) colours
- **Ancillary revenue** — extra-service uptake and earners
- **Payment mix** — tender split


<img width="1308" height="733" alt="image" src="https://github.com/user-attachments/assets/f91284b7-426f-4e21-9636-2df67b4b7aff" />

---

## How to run it

1. Load the raw data into a `tembo_hotel.staging_tembo` table (all text columns).
2. Run `tembo_clean_load.sql` to build and populate `tembo_bookings`.
3. Run `tembo_views_layer.sql` to create the views and the `bi_reader` role.
4. Connect Power BI (Get Data → PostgreSQL) as `bi_reader`, load `v_stays`,
   apply the theme, and build the report.

---

## Tools

PostgreSQL · DBeaver · Power BI Desktop · SQL (CTEs, window functions, views)

## Author

Joy 
