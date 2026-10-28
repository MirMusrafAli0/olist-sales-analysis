/* ============================================================
   OLIST E-COMMERCE SALES ANALYSIS  (MySQL 8+)
   Part 1: Create database and tables
   Part 2: Load CSV data
   Part 3: Analysis queries
   ============================================================ */


/* ------------------------------------------------------------
   PART 1: CREATE DATABASE AND TABLES
   ------------------------------------------------------------ */
CREATE DATABASE IF NOT EXISTS olist;
USE olist;

DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS category_translation;

CREATE TABLE customers (
    customer_id        VARCHAR(32) PRIMARY KEY,
    customer_unique_id VARCHAR(32),
    customer_city      VARCHAR(100),
    customer_state     CHAR(2)
);

CREATE TABLE orders (
    order_id                      VARCHAR(32) PRIMARY KEY,
    customer_id                   VARCHAR(32),
    order_status                  VARCHAR(20),
    order_purchase_timestamp      DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME
);

CREATE TABLE order_items (
    order_id      VARCHAR(32),
    order_item_id INT,
    product_id    VARCHAR(32),
    price         DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE products (
    product_id            VARCHAR(32) PRIMARY KEY,
    product_category_name VARCHAR(100)
);

CREATE TABLE category_translation (
    product_category_name         VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100)
);


/* ------------------------------------------------------------
   PART 2: LOAD CSV DATA
   Before running:
   1. Change the file paths below to where YOU saved the CSVs
      (use forward slashes, e.g. C:/olist/olist_orders_dataset.csv)
   2. Run:  SET GLOBAL local_infile = 1;
   3. In MySQL Workbench: edit your connection ->
      Advanced -> "Others" box -> add:  OPT_LOCAL_INFILE=1
      then reconnect.
   If your file has Windows line endings and rows load wrong,
   change '\n' to '\r\n'.
   ------------------------------------------------------------ */
SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE 'C:/olist/olist_customers_dataset.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(customer_id, customer_unique_id, @zip, customer_city, customer_state);

LOAD DATA LOCAL INFILE 'C:/olist/olist_orders_dataset.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, customer_id, order_status, @purchase, @approved, @carrier, @delivered, @estimated)
SET order_purchase_timestamp      = NULLIF(@purchase, ''),
    order_delivered_customer_date = NULLIF(@delivered, ''),
    order_estimated_delivery_date = NULLIF(@estimated, '');

LOAD DATA LOCAL INFILE 'C:/olist/olist_order_items_dataset.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, order_item_id, product_id, @seller, @ship_limit, price, freight_value);

LOAD DATA LOCAL INFILE 'C:/olist/olist_products_dataset.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_id, @category, @n1, @n2, @n3, @n4, @n5, @n6, @n7)
SET product_category_name = NULLIF(@category, '');

LOAD DATA LOCAL INFILE 'C:/olist/product_category_name_translation.csv'
INTO TABLE category_translation
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Quick check: expected roughly 99k customers, 99k orders, 112k order items, 32k products
SELECT 'customers' AS tbl, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation;


/* ------------------------------------------------------------
   PART 3: ANALYSIS QUERIES
   Revenue = SUM(price) of items in DELIVERED orders only.
   ------------------------------------------------------------ */

-- Q1. Overall business KPIs
SELECT
    ROUND(SUM(oi.price), 2)                                   AS total_revenue,
    COUNT(DISTINCT o.order_id)                                AS total_orders,
    COUNT(DISTINCT c.customer_unique_id)                      AS total_customers,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2)      AS avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN customers c    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered';


-- Q2. Monthly revenue and order count
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    ROUND(SUM(oi.price), 2)                          AS revenue,
    COUNT(DISTINCT o.order_id)                       AS orders
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY order_month
ORDER BY order_month;


-- Q3. Month-over-month revenue growth (%)
WITH monthly AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        SUM(oi.price)                                    AS revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY order_month
)
SELECT
    order_month,
    ROUND(revenue, 2) AS revenue,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY order_month))
          / LAG(revenue) OVER (ORDER BY order_month) * 100, 2) AS mom_growth_pct
FROM monthly
ORDER BY order_month;


-- Q4. Top 10 products by revenue
SELECT
    oi.product_id,
    COALESCE(t.product_category_name_english, 'unknown') AS category,
    ROUND(SUM(oi.price), 2)                              AS revenue,
    COUNT(*)                                             AS units_sold
FROM order_items oi
JOIN orders o             ON oi.order_id = o.order_id
LEFT JOIN products p      ON oi.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY oi.product_id, category
ORDER BY revenue DESC
LIMIT 10;


-- Q5. Top 10 categories by revenue
SELECT
    COALESCE(t.product_category_name_english, 'unknown') AS category,
    ROUND(SUM(oi.price), 2)                              AS revenue,
    COUNT(DISTINCT o.order_id)                           AS orders
FROM order_items oi
JOIN orders o             ON oi.order_id = o.order_id
LEFT JOIN products p      ON oi.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY category
ORDER BY revenue DESC
LIMIT 10;


-- Q6. Revenue by customer state
SELECT
    c.customer_state,
    ROUND(SUM(oi.price), 2)      AS revenue,
    COUNT(DISTINCT o.order_id)   AS orders
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN customers c    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY revenue DESC;


-- Q7. Average order value by state
SELECT
    c.customer_state,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
JOIN customers c    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY avg_order_value DESC;


-- Q8. Repeat customer rate
WITH customer_orders AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                             AS total_customers,
    SUM(order_count > 1)                                 AS repeat_customers,
    ROUND(SUM(order_count > 1) / COUNT(*) * 100, 2)      AS repeat_rate_pct
FROM customer_orders;


-- Q9. Average delivery time (days) by state
SELECT
    c.customer_state,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                       o.order_purchase_timestamp)), 1) AS avg_delivery_days
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;


-- Q10. Late delivery rate (delivered after the estimated date)
SELECT
    COUNT(*)                                                     AS delivered_orders,
    SUM(order_delivered_customer_date > order_estimated_delivery_date) AS late_orders,
    ROUND(SUM(order_delivered_customer_date > order_estimated_delivery_date)
          / COUNT(*) * 100, 2)                                   AS late_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;
