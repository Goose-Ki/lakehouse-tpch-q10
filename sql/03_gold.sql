-- GOLD: витрина — топ-20 клиентов по выручке от возвратов за Q4 1993 (ответ на Q10).

DROP TABLE IF EXISTS lakehouse.gold.top20_returned_customers;

CREATE TABLE lakehouse.gold.top20_returned_customers
WITH (format = 'PARQUET') AS
SELECT
  c.custkey,
  c.name,
  sum(r.net_revenue) AS revenue,
  c.acctbal,
  c.nation,
  c.address,
  c.phone,
  c.comment
FROM lakehouse.silver.returned_lines  AS r
JOIN lakehouse.silver.customer_nation AS c ON r.custkey = c.custkey
WHERE r.orderdate >= DATE '1993-10-01'
  AND r.orderdate <  DATE '1994-01-01'
GROUP BY c.custkey, c.name, c.acctbal, c.nation, c.address, c.phone, c.comment
ORDER BY revenue DESC
LIMIT 20;
