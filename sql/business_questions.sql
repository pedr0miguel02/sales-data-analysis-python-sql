-- =====================================================================
-- Business questions - Sales analysis (SQLite)
-- Database: data/sales.db (created by notebooks/01_data_cleaning.ipynb)
-- Tables: customers, products, orders, order_items
-- =====================================================================


-- ---------------------------------------------------------------------
-- A. Sales performance
-- ---------------------------------------------------------------------

-- Q1. What are the revenue, profit and margin in each year?
SELECT
    strftime('%Y', o.order_date)                       AS year,
    COUNT(DISTINCT o.order_id)                         AS orders,
    COUNT(DISTINCT o.customer_id)                      AS customers,
    ROUND(SUM(oi.sales), 0)                            AS revenue,
    ROUND(SUM(oi.profit), 0)                           AS profit,
    ROUND(SUM(oi.profit) * 100.0 / SUM(oi.sales), 1)   AS margin_pct,
    ROUND(SUM(oi.sales) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM order_items oi
JOIN orders o ON oi.order_id = o.order_id
GROUP BY year
ORDER BY year;

-- Q2. How did revenue change month by month in 2024, compared with the previous month and with the same month of 2023?
WITH monthly AS (
    SELECT
        strftime('%Y-%m', o.order_date) AS month,
        SUM(oi.sales)                   AS revenue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    GROUP BY month
),
with_previous AS (
    SELECT
        month,
        revenue,
        LAG(revenue, 1)  OVER (ORDER BY month) AS previous_month,
        LAG(revenue, 12) OVER (ORDER BY month) AS same_month_last_year
    FROM monthly
)
SELECT
    month,
    ROUND(revenue, 0)                                                   AS revenue,
    ROUND((revenue - previous_month) * 100.0 / previous_month, 1)       AS vs_previous_month_pct,
    ROUND((revenue - same_month_last_year) * 100.0 / same_month_last_year, 1) AS vs_last_year_pct
FROM with_previous
WHERE month >= '2024-01'
ORDER BY month;

-- Q3. How fast is the yearly revenue accumulated? (running total)
WITH monthly AS (
    SELECT
        strftime('%Y', o.order_date) AS year,
        strftime('%m', o.order_date) AS month,
        SUM(oi.sales)                AS revenue
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    GROUP BY year, month
)
SELECT
    year,
    month,
    ROUND(revenue, 0) AS revenue,
    ROUND(SUM(revenue) OVER (PARTITION BY year ORDER BY month), 0) AS running_total,
    ROUND(SUM(revenue) OVER (PARTITION BY year ORDER BY month) * 100.0
          / SUM(revenue) OVER (PARTITION BY year), 1)              AS pct_of_year
FROM monthly
WHERE year = '2024'
ORDER BY month;

-- Q4. Is the Christmas peak the same for every category?
SELECT
    p.category,
    ROUND(SUM(oi.sales), 0) AS revenue,
    ROUND(SUM(CASE WHEN strftime('%m', o.order_date) IN ('11', '12') THEN oi.sales ELSE 0 END), 0) AS revenue_nov_dec,
    ROUND(SUM(CASE WHEN strftime('%m', o.order_date) IN ('11', '12') THEN oi.sales ELSE 0 END) * 100.0
          / SUM(oi.sales), 1) AS pct_in_nov_dec
FROM order_items oi
JOIN orders o   ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category
ORDER BY revenue DESC;


-- ---------------------------------------------------------------------
-- B. Products and discounts
-- ---------------------------------------------------------------------

-- Q5. What are the top 3 products in each category by revenue?
WITH product_sales AS (
    SELECT
        p.category,
        p.product_name,
        SUM(oi.sales)    AS revenue,
        SUM(oi.profit)   AS profit,
        SUM(oi.quantity) AS units
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY p.category, p.product_name
),
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank_in_category
    FROM product_sales
)
SELECT
    category,
    rank_in_category,
    product_name,
    units,
    ROUND(revenue, 0) AS revenue,
    ROUND(profit, 0)  AS profit
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;

-- Q6. Which sub-categories have a margin below the company average?
SELECT
    p.category,
    p.sub_category,
    ROUND(SUM(oi.sales), 0)                          AS revenue,
    ROUND(SUM(oi.profit) * 100.0 / SUM(oi.sales), 1) AS margin_pct,
    (SELECT ROUND(SUM(profit) * 100.0 / SUM(sales), 1) FROM order_items) AS company_margin_pct
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category, p.sub_category
HAVING SUM(oi.profit) * 1.0 / SUM(oi.sales) < (SELECT SUM(profit) * 1.0 / SUM(sales) FROM order_items)
ORDER BY margin_pct;

-- Q7. How do discounts affect sales and profit?
SELECT
    CASE
        WHEN discount = 0     THEN '1. No discount'
        WHEN discount <= 0.10 THEN '2. Low (5-10%)'
        WHEN discount <= 0.20 THEN '3. Medium (15-20%)'
        ELSE                       '4. High (25-30%)'
    END                                           AS discount_band,
    COUNT(*)                                      AS lines,
    ROUND(AVG(quantity), 2)                       AS avg_units,
    ROUND(SUM(sales), 0)                          AS revenue,
    ROUND(SUM(profit), 0)                         AS profit,
    ROUND(SUM(profit) * 100.0 / SUM(sales), 1)    AS margin_pct
FROM order_items
GROUP BY discount_band
ORDER BY discount_band;

-- Q8. Which products are being sold at a loss, and how much do we lose?
SELECT
    p.product_name,
    oi.discount,
    COUNT(*)                 AS lines_at_loss,
    ROUND(SUM(oi.sales), 0)  AS revenue,
    ROUND(SUM(oi.profit), 0) AS total_loss
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
WHERE oi.profit < 0
GROUP BY p.product_name, oi.discount
ORDER BY total_loss;


-- ---------------------------------------------------------------------
-- C. Customers
-- ---------------------------------------------------------------------

-- Q9. Who are the 10 best customers?
SELECT
    c.customer_id,
    c.customer_name,
    c.segment,
    c.state,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(oi.sales), 0)    AS revenue,
    ROUND(SUM(oi.profit), 0)   AS profit
FROM customers c
JOIN orders o       ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.customer_name, c.segment, c.state
ORDER BY revenue DESC
LIMIT 10;

-- Q10. How are customers split by how often they buy, and how much is each group worth?
WITH customer_orders AS (
    SELECT
        o.customer_id,
        COUNT(DISTINCT o.order_id) AS n_orders,
        SUM(oi.sales)              AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    GROUP BY o.customer_id
)
SELECT
    CASE
        WHEN n_orders = 1   THEN '1. One-time (1 order)'
        WHEN n_orders <= 5  THEN '2. Occasional (2-5 orders)'
        WHEN n_orders <= 10 THEN '3. Regular (6-10 orders)'
        ELSE                     '4. Loyal (11+ orders)'
    END                                                                  AS customer_group,
    COUNT(*)                                                             AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_orders), 1)  AS pct_customers,
    ROUND(SUM(revenue) * 100.0 / (SELECT SUM(revenue) FROM customer_orders), 1) AS pct_revenue,
    ROUND(AVG(revenue), 0)                                               AS avg_revenue_per_customer
FROM customer_orders
GROUP BY customer_group
ORDER BY customer_group;

-- Q11. How many new customers do we get each month?
WITH first_order AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_order_date
    FROM orders
    GROUP BY customer_id
)
SELECT
    strftime('%Y-%m', first_order_date) AS month,
    COUNT(*)                            AS new_customers
FROM first_order
GROUP BY month
ORDER BY month;

-- Q12. How does each region contribute to revenue and profit?
SELECT
    c.region,
    COUNT(DISTINCT c.customer_id)                                   AS customers,
    ROUND(SUM(oi.sales), 0)                                         AS revenue,
    ROUND(SUM(oi.sales) * 100.0 / SUM(SUM(oi.sales)) OVER (), 1)    AS pct_of_revenue,
    ROUND(SUM(oi.profit) * 100.0 / SUM(oi.sales), 1)                AS margin_pct,
    ROUND(SUM(oi.sales) / COUNT(DISTINCT c.customer_id), 0)         AS revenue_per_customer
FROM order_items oi
JOIN orders o    ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.region
ORDER BY revenue DESC;


-- ---------------------------------------------------------------------
-- D. Operations
-- ---------------------------------------------------------------------

-- Q13. How long does each shipping mode take, and is "Same Day" really same day?
SELECT
    ship_mode,
    COUNT(*)                                                     AS orders,
    ROUND(AVG(julianday(ship_date) - julianday(order_date)), 2)  AS avg_days_to_ship,
    ROUND(AVG(julianday(deliver_date) - julianday(order_date)), 2) AS avg_days_to_deliver,
    SUM(CASE WHEN ship_date = order_date THEN 1 ELSE 0 END)      AS shipped_on_order_day
FROM orders
GROUP BY ship_mode
ORDER BY avg_days_to_deliver;

-- Q14. What is the return rate by category, and how much revenue is returned?
SELECT
    p.category,
    COUNT(*)                                                          AS lines,
    SUM(oi.is_returned)                                               AS returned_lines,
    ROUND(AVG(oi.is_returned) * 100, 1)                               AS return_rate_pct,
    ROUND(SUM(CASE WHEN oi.is_returned = 1 THEN oi.sales ELSE 0 END), 0) AS returned_revenue
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
GROUP BY p.category
ORDER BY return_rate_pct DESC;
