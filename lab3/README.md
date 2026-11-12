# ЛР-3. Аналитический дашборд для бизнес-кейса — вариант 6

**Студент:** Буц Игорь Денисович · **группа:** БД-251м
**Бизнес-кейс:** Когортный анализ повторных покупок

## Цель работы
Какая доля клиентов каждой когорты (месяц первой покупки) возвращается в следующие месяцы?

## Исследуемые метрики
- **Удержание, %** = `SUM([active_customers]) / SUM([cohort_size]) * 100`

## Архитектура решения
Kaggle (Olist, 9 CSV) → Python (`urllib`, `pandas`) → SQLite: RAW → STAGING → CORE → витрина `dm_v06_cohorts` → CSV → Yandex DataLens.

## Технологический стек
Python 3.13.18, pandas 2.2.3, SQLite 3.45.1, Google Colab / Jupyter, Yandex DataLens.

## Схема данных
Слои: `raw_*` (9 таблиц) → `stg_*` (типизация, очистка) → `core_order`, `core_item`, `dim_state` → `dm_v06_cohorts` (VIEW).
<!-- вставьте скриншот или ER-диаграмму: img/er.png -->

## SQL витрины
```sql
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
ORDER BY g.cohort_month, g.month_offset
```

## Контрольные значения
| Вопрос | Ответ |
|---|---|
| Среднее удержание через 1 месяц, % | 0.48 |
| Когорта с наибольшим числом клиентов | 2017-11-01 |

Значения совпадают с дашбордом: точка 1 на кривой удержания = 0,48 %, самый высокий столбец «Размера когорт» — 2017-11.
Удержание считается как SUM(active_customers) / SUM(cohort_size), а не среднее процентов: иначе когорта
2017-01 (717 клиентов) весила бы столько же, сколько 2017-11 (7 060).

## Дашборд DataLens
[Ссылка на дашборд](https://datalens.yandex/conyx4p1hc86v?_share_link=public)

| № | Тип | Название |
|---|---|---|
| 1 | Индикатор | Клиентов в когортах |
| 2 | Сводная таблица | Матрица удержания, % |
| 3 | Линейная диаграмма | Кривая удержания |
| 4 | Столбчатая диаграмма | Размер когорт |
| 5 | Кольцевая диаграмма | Первые и повторные клиент-месяцы |
| 6 | Комбинированная диаграмма | Возвраты и удержание |

![Дашборд](img/dashboard.png)

## Выводы и бизнес-рекомендации
1. Клиенты почти не возвращаются, поэтому стоит работать с ними сразу после первой покупки. По витрине через месяц после первой покупки возвращаются всего 0,48 % клиентов, через полгода 0,23 %, через год 0,17 %. За весь период больше одного заказа сделали только 3 % покупателей (2 801 из 93 358). Сильнее всего удержание падает между первым и третьим месяцем: с 0,48 % до 0,26 %. Поэтому можно предложить в первые 30 дней после доставки отправлять клиенту письмо с купоном на следующий заказ. Проверить эффект можно A/B-тестом: сравнить удержание через месяц у тех, кто получил купон, и у тех, кто не получил.
2. Рост маркетплейса держится только на новых клиентах. Когорты выросли с 717 человек в январе 2017 года до 6–7 тысяч в месяц в 2018 году, а доля вернувшихся при этом не выросла. Удержание через месяц у когорт 2018 года даже немного ниже, чем у 2017-го: 0,45 % против 0,52 %. Получается, что как только приток новых покупателей замедлится, выручка тоже упадёт. Я считаю, что удержание нужно добавить в регулярные метрики наравне с привлечением и смотреть его каждый месяц на таком же когортном дашборде.
3. Больше всего клиентов приходит с акций, но они возвращаются хуже остальных. Самая большая когорта — ноябрь 2017 года (7 060 клиентов), скорее всего из-за «Чёрной пятницы». Но через полгода у неё самое низкое удержание: 0,11 %. Лучше всего возвращались клиенты, пришедшие в августе–октябре 2017 года (0,69–0,72 % через месяц). Поэтому я бы оценивал акции не только по числу новых покупателей, но и по тому, сколько из них вернулось через 1–3 месяца.
