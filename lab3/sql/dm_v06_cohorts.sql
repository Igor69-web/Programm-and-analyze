DROP VIEW IF EXISTS dm_v06_cohorts;
CREATE VIEW dm_v06_cohorts AS
WITH RECURSIVE
orders AS (                                   -- покупки: доставленные заказы
    SELECT customer_unique_id, purchase_month
    FROM core_order
    WHERE order_status = 'delivered'
),
first_purchase AS (                           -- когорта = месяц первой покупки
    SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
    FROM orders
    GROUP BY customer_unique_id
),
cohort_size AS (                              -- размер когорты, полный период
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM first_purchase
    WHERE cohort_month BETWEEN '2017-01-01' AND '2018-08-01'
    GROUP BY cohort_month
),
activity AS (                                 -- активные клиенты когорты по смещению
    SELECT f.cohort_month,
           (CAST(strftime('%Y', o.purchase_month) AS INTEGER) * 12 + CAST(strftime('%m', o.purchase_month) AS INTEGER))
         - (CAST(strftime('%Y', f.cohort_month)   AS INTEGER) * 12 + CAST(strftime('%m', f.cohort_month)   AS INTEGER))
               AS month_offset,
           COUNT(DISTINCT o.customer_unique_id) AS active_customers
    FROM orders o
    JOIN first_purchase f USING (customer_unique_id)
    WHERE o.purchase_month <= '2018-08-01'
    GROUP BY 1, 2
),
offsets(n) AS (                               -- смещения 0 … 19 (2017-01 → 2018-08)
    SELECT 0 UNION ALL SELECT n + 1 FROM offsets WHERE n < 19
),
grid AS (                                     -- полная сетка: только наблюдаемые смещения
    SELECT c.cohort_month, o.n AS month_offset, c.cohort_size
    FROM cohort_size c
    JOIN offsets o ON date(c.cohort_month, '+' || o.n || ' months') <= '2018-08-01'
)
SELECT g.cohort_month,
       g.month_offset,
       date(g.cohort_month, '+' || g.month_offset || ' months')          AS activity_month,
       COALESCE(a.active_customers, 0)                                    AS active_customers,
       g.cohort_size,
       ROUND(100.0 * COALESCE(a.active_customers, 0) / g.cohort_size, 2) AS retention_pct,
       CASE WHEN g.month_offset = 0 THEN 'Первая покупка' ELSE 'Повторная покупка' END AS purchase_type
FROM grid g
LEFT JOIN activity a USING (cohort_month, month_offset)
ORDER BY g.cohort_month, g.month_offset;
