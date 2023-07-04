use gdb023;
-- 1. Let's highlight the tables and columns we want to work with
DROP TEMPORARY TABLE financials_ini;

CREATE TEMPORARY TABLE financials_ini
SELECT 
    s.date AS date,
    s.fiscal_year,
    dp.product AS product,
    dp.segment,
    dp.division,
    dp.category,
    dp.variant,
    dc.customer AS customer,
    dc.channel,
    dc.market,
    dc.platform,
    dc.region,
    s.sold_quantity AS qty_sold,
    fm.manufacturing_cost AS manufacturing_unit_cost,
    fp.pre_invoice_discount_pct AS invoice_deductions,
    gp.gross_price AS unit_price,
    s.sold_quantity * fm.manufacturing_cost as manufacturing_cost,
    s.sold_quantity * gp.gross_price as total_price,
    s.sold_quantity * gp.gross_price * (1- fp.pre_invoice_discount_pct) as revenue,
    (s.sold_quantity * gp.gross_price * (1- fp.pre_invoice_discount_pct)) - (s.sold_quantity * fm.manufacturing_cost) as profit_margin
FROM
    fact_sales_monthly s
        JOIN
    dim_product dp ON s.product_code = dp.product_code
        JOIN
    dim_customer dc ON s.customer_code = dc.customer_code
        JOIN
    fact_manufacturing_cost fm ON s.product_code = fm.product_code and s.fiscal_year = fm.cost_year
        JOIN
    fact_pre_invoice_deductions fp ON s.customer_code = fp.customer_code and s.fiscal_year = fp.fiscal_year
        JOIN
    fact_gross_price gp ON s.product_code = gp.product_code and s.fiscal_year = gp.fiscal_year
;
-- 2. total sales by year
SELECT 
    SUM(total_price)
FROM
    financials_ini
GROUP BY fiscal_year;

-- 2. Financials by customer
SELECT 
    customer,
    market,
    channel,
    SUM(revenue) AS revenue,
    SUM(qty_sold) as qty_sold,
    fiscal_year,
    (total_price - revenue) AS discount_cost
FROM
    financials_ini
GROUP BY customer , market , fiscal_year
ORDER BY revenue DESC;

-- 3. Financials by Product
SELECT 
    product,
    segment,
    ROUND(SUM(revenue), 2) AS revenue,
    ROUND(SUM(profit_margin), 2) AS profit,
    SUM(qty_sold) AS quantity_sold,
    fiscal_year,
    ROUND(AVG(manufacturing_unit_cost), 2) AS avg_manufacturing_cost,
    ROUND(AVG(unit_price),2) AS avg_unit_price
FROM
    financials_ini
GROUP BY segment , product , fiscal_year
ORDER BY revenue DESC;

-- 4. Increase in Unique products from 2020 to 2021
With product_count_2020 as (SELECT 
    COUNT(DISTINCT product_code) AS product_count_2020,
    fiscal_year
	FROM
		fact_sales_monthly
	WHERE
		fiscal_year = 2020),
    product_count_2021 as (SELECT 
    COUNT(DISTINCT product_code) AS product_count_2021,
    fiscal_year
	FROM
		fact_sales_monthly
	WHERE
		fiscal_year = 2021)
SELECT
p1.product_count_2020, p2.product_count_2021, 
CONCAT(ROUND(((ABS(p1.product_count_2020 - p2.product_count_2021)/p1.product_count_2020) * 100),2),'%') as percentage_chg
FROM
product_count_2020 p1
CROSS JOIN
product_count_2021 p2;

-- 5. Segments with the highest increase in unique products
With p_2020 as (SELECT 
    COUNT(DISTINCT s.product_code) AS product_count_2020,
    s.fiscal_year,
    p.segment as segment
	FROM
		fact_sales_monthly s
        JOIN
        dim_product p ON s.product_code = p.product_code
        where s.fiscal_year = 2020
	GROUP BY segment
	),
    p_2021 as (SELECT 
    COUNT(DISTINCT s.product_code) AS product_count_2021,
    s.fiscal_year,
    p.segment as segment
	FROM
		fact_sales_monthly s
        JOIN
        dim_product p ON s.product_code = p.product_code
	where s.fiscal_year = 2021
	GROUP BY segment
	)
SELECT 
p1.segment as segment, 
p1.product_count_2020 as product_count_2020,
p2.product_count_2021 as product_count_2021,
ABS(p1.product_count_2020 - p2.product_count_2021) as difference,
ROUND(ABS(p1.product_count_2020 - p2.product_count_2021)/p1.product_count_2020,2)*100 as pct_increase
FROM
p_2020 p1 
JOIN 
p_2021 p2 ON p1.segment = p2.segment
GROUP BY segment
ORDER BY difference DESC;

-- 6. Channel that brought the most gross sales
WITH gross_sales AS(
	SELECT
	SUM(sold_quantity) AS gross_sales_mln
	FROM
	fact_sales_monthly)
SELECT 
	c.channel AS channel,
	ROUND((sum(s.sold_quantity)/g.gross_sales_mln) * 100,2) AS percentage,
	g.gross_sales_mln
FROM
	dim_customer c 
JOIN
	fact_sales_monthly s 
    ON 
		c.customer_code = s.customer_code
		CROSS JOIN
		gross_sales g 
GROUP BY channel
ORDER BY percentage DESC
;

-- 7. product segment demand by country
SELECT 
    p.segment AS segment,
    dc.market AS market,
    dc.customer AS customer,
    SUM(s.sold_quantity) AS total_sold_quantity
FROM
    fact_sales_monthly s
        JOIN
    dim_product p ON s.product_code = p.product_code
        JOIN
    dim_customer dc ON s.customer_code = dc.customer_code
GROUP BY segment , market , customer
ORDER BY segment , market , total_sold_quantity DESC;


-- 8. Customer Analysis
-- a. how many customers do we have in total
SELECT 
    COUNT(DISTINCT customer) AS customer
FROM
    dim_customer;

-- b. How many new customers were acquired between 2020 & 2021
-- unique customers in 2020
SELECT 
    COUNT(DISTINCT customer_code) AS customers_2020,
    fiscal_year
	FROM
		fact_sales_monthly
	WHERE
		fiscal_year = 2020;
        
-- c. unique customers in 2021
SELECT 
    COUNT(DISTINCT customer_code) AS customers_2021,
    fiscal_year
	FROM
		fact_sales_monthly
	WHERE
		fiscal_year = 2021;

-- 9. Top 10 Customers by quantity sold
SELECT 
    sales_by_customer_2020.*
FROM
    (SELECT 
        dc.customer AS customer,
            SUM(s.sold_quantity) AS qty_sold,
            s.fiscal_year
    FROM
        dim_customer dc
    JOIN fact_sales_monthly s ON dc.customer_code = s.customer_code
    WHERE
        s.fiscal_year = 2020
    GROUP BY customer
    ORDER BY qty_sold DESC
    ) AS sales_by_customer_2020 
UNION SELECT 
    sales_by_customer_2021.*
FROM
    (SELECT 
        dc.customer AS customer,
            SUM(s.sold_quantity) AS qty_sold,
            s.fiscal_year
    FROM
        dim_customer dc
    JOIN fact_sales_monthly s ON dc.customer_code = s.customer_code
    WHERE
        s.fiscal_year = 2021
    GROUP BY customer
    ORDER BY qty_sold DESC
    ) AS sales_by_customer_2021
ORDER BY customer, fiscal_year DESC;

-- 10. Sales by country
SELECT 
    year_2020.*
FROM
    (SELECT 
        dc.market AS country,
            SUM(s.sold_quantity) AS qty_sold,
            s.fiscal_year AS year
    FROM
        dim_customer dc
    JOIN fact_sales_monthly s ON dc.customer_code = s.customer_code
    GROUP BY country
    HAVING s.fiscal_year = '2020') AS year_2020 
UNION SELECT 
    year_2021.*
FROM
    (SELECT 
        dc.market AS country,
            SUM(s.sold_quantity) AS qty_sold,
            s.fiscal_year AS year
    FROM
        dim_customer dc
    JOIN fact_sales_monthly s ON dc.customer_code = s.customer_code
    WHERE
        s.fiscal_year = '2021'
    GROUP BY country) AS year_2021
ORDER BY qty_sold DESC;


-- 11. sales by product segment and change in sales quantity
with segment_sales_2020 as(
SELECT 
    p.segment AS segment,
    COUNT(DISTINCT p.product_code) AS product_count,
    SUM(s.sold_quantity) AS qty_sold,
    s.fiscal_year as calendar_year
FROM
    dim_product p
        JOIN
    fact_sales_monthly s ON p.product_code = s.product_code
WHERE
    s.fiscal_year = 2020
GROUP BY segment
ORDER BY product_count DESC),
segment_sales_2021 as(
SELECT 
    p.segment AS segment,
    COUNT(DISTINCT p.product_code) AS product_count,
    SUM(s.sold_quantity) AS qty_sold,
    s.fiscal_year as calendar_year
FROM
    dim_product p
        JOIN
    fact_sales_monthly s ON p.product_code = s.product_code
WHERE
    s.fiscal_year = 2021
GROUP BY segment
ORDER BY product_count DESC)
select
s1.segment as segment, s1.qty_sold as qty_sold_2020, s2.qty_sold as qty_sold_2021, 
(s2.qty_sold - s1.qty_sold) as difference,
round((ABS(s1.qty_sold - s2.qty_sold)/s1.qty_sold)*100, 2) as pct_change
FROM
segment_sales_2020 s1
join
segment_sales_2021 s2 on s1.segment = s2.segment;
 
 
