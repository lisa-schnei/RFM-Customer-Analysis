
# Understanding spread of the data for relevant columns
-- Min: 2010-12-01; Max: 2011-12-09
-- quantity has negative values
-- UnitPrice can also have negative values; highest 38,970
SELECT MIN(InvoiceDate) AS min_date,
MAX(InvoiceDate) AS max_date,
MIN(Quantity) AS min_qty,
MAX(Quantity) AS max_qty,
MIN(UnitPrice) AS min_price,
MAX(UnitPrice) AS max_price
FROM `turing_data_analytics.rfm`;


# Checking for NULL values in relevant data
-- 516,384 total records with 127,216 NULL values in CustomerID (25% of data has no customerID)
-- Max date here is 2011-11-30
SELECT
COUNT(*) AS number_rows,
MIN(InvoiceDate) AS min_invoicedate,
MAX(InvoiceDate) AS max_invoicedate,
SUM(CASE WHEN Quantity IS NULL THEN 1 ELSE 0 END) AS null_quantity,
SUM(CASE WHEN InvoiceDate IS NULL THEN 1 ELSE 0 END) AS null_invoicedate,
SUM(CASE WHEN UnitPrice IS NULL THEN 1 ELSE 0 END) AS null_unitprice,
SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS null_customerid
FROM `turing_data_analytics.rfm`
WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01';

# Checking if data is available for 2011-12-01
-- No data available
SELECT *
FROM `turing_data_analytics.rfm`
WHERE InvoiceDate = '2011-12-01';

# Checking number of individual customers in the data
-- 4,332 customers incl. NULL values in customerIDs
SELECT CustomerID,
COUNT(*) AS records_per_customer,
SUM(COUNT(*)) OVER () AS total_records
FROM (SELECT * FROM `turing_data_analytics.rfm` WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01')
GROUP BY 1
ORDER BY 2 DESC;

# Investigating further into the records with NULL customerID
-- 3,722 different InvoiceNo records with CustomerID NULL
SELECT CustomerID,
InvoiceNo,
InvoiceDate,
COUNT(*) AS record_count
FROM `turing_data_analytics.rfm`
GROUP BY 1,2,3
HAVING CustomerID IS NULL;

-- Not having customerIDs for part of the data affects the ability to calculate RFM scores. I will therefore exclude the data with missing customerIDs from the analysis.
-- Additionally, I will also exclude all records with negative values for Quantity and UnitPrice as these are likely returns and in the final RFM table I would otherwise end up with negative monetary value.
-- 389,168 records left for analysis
SELECT *
FROM `turing_data_analytics.rfm`
WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
  AND CustomerID IS NOT NULL;


# Orders with negative quantities all have InvoiceNo starting with 'C'
-- These are likely returns, and will be excluded from the analysis. If I keep them included, they will create negative monetary values in the rfm table for some customers.
SELECT *
FROM `turing_data_analytics.rfm`
  WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
    AND CustomerID IS NOT NULL
    AND Quantity < 0
ORDER BY CustomerID

# Calculating recency and checking results
-- Important to note that DATE_DIFF function here counts full days
SELECT CustomerID,
InvoiceDate,
TIMESTAMP('2011-12-01') AS reference,
DATE_DIFF(TIMESTAMP '2011-12-01', MAX(InvoiceDate), DAY) AS recency
FROM `turing_data_analytics.rfm`
WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
  AND CustomerID IS NOT NULL
  AND InvoiceNo NOT LIKE 'C%'
GROUP BY 1, 2, 3;

# Computing RFM table
SELECT CustomerID,
DATE_DIFF(TIMESTAMP '2011-12-01', MAX(InvoiceDate), DAY) AS recency,
COUNT(DISTINCT InvoiceNo) AS frequency,
SUM(Quantity * UnitPrice) AS monetary
FROM (
  SELECT *,
  TIMESTAMP('2011-12-01') AS reference,
  FROM `turing_data_analytics.rfm`
  WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
    AND CustomerID IS NOT NULL
    AND InvoiceNo NOT LIKE 'C%')
GROUP BY 1
ORDER BY 1;

# Checking several records for data validation
SELECT *,
COUNT(DISTINCT InvoiceNo) OVER(PARTITION BY CustomerID) AS frequency,
SUM(Quantity * UnitPrice) OVER(PARTITION BY CustomerID) AS monetary
FROM `turing_data_analytics.rfm`
  WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
    AND CustomerID IS NOT NULL
    AND InvoiceNo NOT LIKE 'C%'
    AND CustomerID IN (12748, 12346)




# Setting up quantile table
WITH rfm_table AS (
  SELECT CustomerID,
DATE_DIFF(TIMESTAMP '2011-12-01', MAX(InvoiceDate), DAY) AS recency,
COUNT(DISTINCT InvoiceNo) AS frequency,
SUM(Quantity * UnitPrice) AS monetary
FROM (
  SELECT *,
  TIMESTAMP('2011-12-01') AS reference,
  FROM `turing_data_analytics.rfm`
  WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
    AND CustomerID IS NOT NULL
    AND InvoiceNo NOT LIKE 'C%')
GROUP BY 1
)

SELECT APPROX_QUANTILES(recency, 4) AS recency_quantiles,
APPROX_QUANTILES(frequency, 4) AS frequency_quantiles,
APPROX_QUANTILES(ROUND(monetary,1), 4) AS monetary_quantiles
FROM rfm_Table

# Computing quantiles table
WITH rfm_table AS (
  SELECT CustomerID,
  DATE_DIFF(TIMESTAMP '2011-12-01', MAX(InvoiceDate), DAY) AS recency,
  COUNT(DISTINCT InvoiceNo) AS frequency,
  SUM(Quantity * UnitPrice) AS monetary
  FROM (
    SELECT *,
    TIMESTAMP('2011-12-01') AS reference,
    FROM `turing_data_analytics.rfm`
    WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
      AND CustomerID IS NOT NULL
      AND InvoiceNo NOT LIKE 'C%')
  GROUP BY 1
)

SELECT
a.*,
r.perc[offset(25)] AS r25,
r.perc[offset(50)] AS r50,
r.perc[offset(75)] AS r75,
f.perc[offset(25)] AS f25,
f.perc[offset(50)] AS f50,
f.perc[offset(75)] AS f75,
m.perc[offset(25)] AS m25,
m.perc[offset(50)] AS m50,
m.perc[offset(75)] AS m75
FROM rfm_table AS a,
  (SELECT APPROX_QUANTILES(monetary, 100) perc FROM rfm_table) AS m,
  (SELECT APPROX_QUANTILES(frequency, 100) perc FROM rfm_table) AS f,
  (SELECT APPROX_QUANTILES(recency, 100) perc FROM rfm_table) AS r
GROUP BY ALL


# Assigning RFM scores based on RFM values and quantiles.
WITH rfm_table AS (
    SELECT CustomerID,
  DATE_DIFF(TIMESTAMP '2011-12-01', MAX(InvoiceDate), DAY) AS recency,
  COUNT(DISTINCT InvoiceNo) AS frequency,
  SUM(Quantity * UnitPrice) AS monetary
  FROM (
    SELECT *,
    TIMESTAMP('2011-12-01') AS reference,
    FROM `turing_data_analytics.rfm`
    WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
      AND CustomerID IS NOT NULL
      AND InvoiceNo NOT LIKE 'C%')
  GROUP BY 1
),

quantiles_table AS (
  SELECT
  a.*,
  r.perc[offset(25)] AS r25,
  r.perc[offset(50)] AS r50,
  r.perc[offset(75)] AS r75,
  r.perc[offset(100)] AS r100,
  f.perc[offset(25)] AS f25,
  f.perc[offset(50)] AS f50,
  f.perc[offset(75)] AS f75,
  f.perc[offset(100)] AS f100,
  m.perc[offset(25)] AS m25,
  m.perc[offset(50)] AS m50,
  m.perc[offset(75)] AS m75,
  m.perc[offset(100)] AS m100
  FROM rfm_table AS a,
    (SELECT APPROX_QUANTILES(monetary, 100) perc FROM rfm_table) AS m,
    (SELECT APPROX_QUANTILES(frequency, 100) perc FROM rfm_table) AS f,
    (SELECT APPROX_QUANTILES(recency, 100) perc FROM rfm_table) AS r
  GROUP BY ALL
)

SELECT *, 
  FROM (
    SELECT *, 
      CASE WHEN monetary <= m25 THEN 1
      WHEN monetary <= m50 AND monetary > m25 THEN 2 
      WHEN monetary <= m75 AND monetary > m50 THEN 3 
      WHEN monetary <= m100 AND monetary > m75 THEN 4 
    END AS m_score,
    CASE WHEN frequency <= f25 THEN 1
      WHEN frequency <= f50 AND frequency > f25 THEN 2 
      WHEN frequency <= f75 AND frequency > f50 THEN 3 
      WHEN frequency <= f100 AND frequency > f75 THEN 4 
    END AS f_score,
    --Recency scoring is reversed
    CASE WHEN recency <= r25 THEN 4
      WHEN recency <= r50 AND recency > r25 THEN 3
      WHEN recency <= r75 AND recency > r50 THEN 2 
      WHEN recency <= r100 AND recency > r75 THEN 1 
    END AS r_score,
    FROM quantiles_table)

# Computing final RFM score table with scores combined and RFM segments
WITH rfm_table AS (
  SELECT CustomerID,
  Country,
  DATE_DIFF(TIMESTAMP '2011-12-01', MAX(InvoiceDate), DAY) AS recency,
  COUNT(DISTINCT InvoiceNo) AS frequency,
  ROUND(SUM(Quantity * UnitPrice),2) AS monetary
  FROM (
    SELECT *,
    TIMESTAMP('2011-12-01') AS reference,
    FROM `turing_data_analytics.rfm`
    WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
      AND CustomerID IS NOT NULL
      AND InvoiceNo NOT LIKE 'C%')
  GROUP BY 1, 2
),

quantiles_table AS (
  SELECT
  a.*,
  r.perc[offset(25)] AS r25,
  r.perc[offset(50)] AS r50,
  r.perc[offset(75)] AS r75,
  r.perc[offset(100)] AS r100,
  f.perc[offset(25)] AS f25,
  f.perc[offset(50)] AS f50,
  f.perc[offset(75)] AS f75,
  f.perc[offset(100)] AS f100,
  m.perc[offset(25)] AS m25,
  m.perc[offset(50)] AS m50,
  m.perc[offset(75)] AS m75,
  m.perc[offset(100)] AS m100
  FROM rfm_table AS a,
    (SELECT APPROX_QUANTILES(monetary, 100) perc FROM rfm_table) AS m,
    (SELECT APPROX_QUANTILES(frequency, 100) perc FROM rfm_table) AS f,
    (SELECT APPROX_QUANTILES(recency, 100) perc FROM rfm_table) AS r
  GROUP BY ALL
),

score_table AS (
  SELECT *, 
  CONCAT(r_score, f_score, m_score) AS rfm_score
    FROM (
      SELECT *, 
        CASE WHEN monetary <= m25 THEN 1
        WHEN monetary <= m50 AND monetary > m25 THEN 2 
        WHEN monetary <= m75 AND monetary > m50 THEN 3 
        WHEN monetary <= m100 AND monetary > m75 THEN 4 
      END AS m_score,
      CASE WHEN frequency <= f25 THEN 1
        WHEN frequency <= f50 AND frequency > f25 THEN 2 
        WHEN frequency <= f75 AND frequency > f50 THEN 3 
        WHEN frequency <= f100 AND frequency > f75 THEN 4 
      END AS f_score,
      --Recency scoring is reversed
      CASE WHEN recency <= r25 THEN 4
        WHEN recency <= r50 AND recency > r25 THEN 3
        WHEN recency <= r75 AND recency > r50 THEN 2 
        WHEN recency <= r100 AND recency > r75 THEN 1 
      END AS r_score,
      FROM quantiles_table)
)

SELECT
  CustomerID,
  Country,
  recency,
  frequency,
  monetary,
  r_score,
  f_score,
  m_score,
  rfm_score,
  CASE WHEN (r_score = 4 AND f_score = 4 AND m_score =4) THEN 'Best Customers'
    WHEN (r_score IN (3, 4) AND f_score = 4 AND m_score IN (2, 3, 4)) THEN 'Loyal Customers'
    WHEN (r_score = 4 AND f_score = 2 AND m_score IN (1, 2)) THEN 'Promising Customers'
    WHEN (r_score = 4 AND f_score IN (1, 2) AND m_score IN (1, 2, 3)) THEN 'New Customers'
    WHEN (r_score IN (3, 4) AND f_score IN (3, 4) AND m_score IN (2, 3)) THEN 'Potential Loyalist'
    WHEN (r_score IN (1, 2, 3) AND f_score IN ( 2, 3) AND m_score IN (3, 4)) THEN 'Needs Attention'
    WHEN (r_score = 1 AND f_score IN (3, 4) AND m_score IN (2, 3, 4)) THEN 'At Risk'
    WHEN (r_score = 1 AND f_score IN (2, 3) AND m_score IN (3, 4)) THEN 'Cant Lose'
    WHEN (r_score = 1 AND f_score IN (1, 2) AND m_score IN (1, 2)) THEN 'Hibernating'
    WHEN (r_score = 1 AND f_score = 1) THEN 'Slipping / Lost Customers'
    WHEN (r_score = 2 AND f_score = 2) THEN 'About To Sleep'
    WHEN m_score = 4 THEN 'Big Spenders'
    ELSE 'Other Customers'
  END AS rfm_segment
FROM score_table


# Checking number of customers in each RFM segment
WITH rfm_table AS (
  SELECT CustomerID,
  Country,
  DATE_DIFF(TIMESTAMP '2011-12-01', MAX(InvoiceDate), DAY) AS recency,
  COUNT(DISTINCT InvoiceNo) AS frequency,
  ROUND(SUM(Quantity * UnitPrice),2) AS monetary
  FROM (
    SELECT *,
    TIMESTAMP('2011-12-01') AS reference,
    FROM `turing_data_analytics.rfm`
    WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
      AND CustomerID IS NOT NULL
      AND InvoiceNo NOT LIKE 'C%')
  GROUP BY 1, 2
),

quantiles_table AS (
  SELECT
  a.*,
  r.perc[offset(25)] AS r25,
  r.perc[offset(50)] AS r50,
  r.perc[offset(75)] AS r75,
  r.perc[offset(100)] AS r100,
  f.perc[offset(25)] AS f25,
  f.perc[offset(50)] AS f50,
  f.perc[offset(75)] AS f75,
  f.perc[offset(100)] AS f100,
  m.perc[offset(25)] AS m25,
  m.perc[offset(50)] AS m50,
  m.perc[offset(75)] AS m75,
  m.perc[offset(100)] AS m100
  FROM rfm_table AS a,
    (SELECT APPROX_QUANTILES(monetary, 100) perc FROM rfm_table) AS m,
    (SELECT APPROX_QUANTILES(frequency, 100) perc FROM rfm_table) AS f,
    (SELECT APPROX_QUANTILES(recency, 100) perc FROM rfm_table) AS r
  GROUP BY ALL
),

score_table AS (
  SELECT *, 
  CONCAT(r_score, f_score, m_score) AS rfm_score
    FROM (
      SELECT *, 
        CASE WHEN monetary <= m25 THEN 1
        WHEN monetary <= m50 AND monetary > m25 THEN 2 
        WHEN monetary <= m75 AND monetary > m50 THEN 3 
        WHEN monetary <= m100 AND monetary > m75 THEN 4 
      END AS m_score,
      CASE WHEN frequency <= f25 THEN 1
        WHEN frequency <= f50 AND frequency > f25 THEN 2 
        WHEN frequency <= f75 AND frequency > f50 THEN 3 
        WHEN frequency <= f100 AND frequency > f75 THEN 4 
      END AS f_score,
      --Recency scoring is reversed
      CASE WHEN recency <= r25 THEN 4
        WHEN recency <= r50 AND recency > r25 THEN 3
        WHEN recency <= r75 AND recency > r50 THEN 2 
        WHEN recency <= r100 AND recency > r75 THEN 1 
      END AS r_score,
      FROM quantiles_table)
),

rfm_segments AS (
  SELECT
  CustomerID,
  Country,
  recency,
  frequency,
  monetary,
  r_score,
  f_score,
  m_score,
  rfm_score,
  CASE WHEN (r_score = 4 AND f_score = 4 AND m_score =4) THEN 'Best Customers'
    WHEN (r_score IN (3, 4) AND f_score = 4 AND m_score IN (2, 3, 4)) THEN 'Loyal Customers'
    WHEN (r_score = 4 AND f_score = 2 AND m_score IN (1, 2)) THEN 'Promising Customers'
    WHEN (r_score = 4 AND f_score IN (1, 2) AND m_score IN (1, 2, 3)) THEN 'New Customers'
    WHEN (r_score IN (3, 4) AND f_score IN (3, 4) AND m_score IN (2, 3)) THEN 'Potential Loyalist'
    WHEN (r_score IN (1, 2, 3) AND f_score IN ( 2, 3) AND m_score IN (3, 4)) THEN 'Needs Attention'
    WHEN (r_score = 1 AND f_score IN (3, 4) AND m_score IN (2, 3, 4)) THEN 'At Risk'
    WHEN (r_score = 1 AND f_score IN (2, 3) AND m_score IN (3, 4)) THEN 'Cant Lose'
    WHEN (r_score = 1 AND f_score IN (1, 2) AND m_score IN (1, 2)) THEN 'Hibernating'
    WHEN (r_score = 1 AND f_score = 1) THEN 'Slipping / Lost Customers'
    WHEN (r_score = 2 AND f_score = 2) THEN 'About To Sleep'
    WHEN m_score = 4 THEN 'Big Spenders'
    ELSE 'Other Customers'
  END AS rfm_segment
FROM score_table
)

SELECT rfm_segment,
COUNT(*) AS customer_cnt,
SUM(COUNT(*)) OVER () AS total_customers
FROM rfm_segments
GROUP BY 1
ORDER BY 2 DESC



# Trying different RFM segment scoring based on more simplified approach
WITH rfm_table AS (
  SELECT CustomerID,
  Country,
  DATE_DIFF(TIMESTAMP '2011-12-01', MAX(InvoiceDate), DAY) AS recency,
  COUNT(DISTINCT InvoiceNo) AS frequency,
  ROUND(SUM(Quantity * UnitPrice),2) AS monetary
  FROM (
    SELECT *,
    TIMESTAMP('2011-12-01') AS reference,
    FROM `turing_data_analytics.rfm`
    WHERE InvoiceDate BETWEEN '2010-12-01' AND '2011-12-01'
      AND CustomerID IS NOT NULL
      AND InvoiceNo NOT LIKE 'C%')
  GROUP BY 1, 2
),

quantiles_table AS (
  SELECT
  a.*,
  r.perc[offset(25)] AS r25,
  r.perc[offset(50)] AS r50,
  r.perc[offset(75)] AS r75,
  r.perc[offset(100)] AS r100,
  f.perc[offset(25)] AS f25,
  f.perc[offset(50)] AS f50,
  f.perc[offset(75)] AS f75,
  f.perc[offset(100)] AS f100,
  m.perc[offset(25)] AS m25,
  m.perc[offset(50)] AS m50,
  m.perc[offset(75)] AS m75,
  m.perc[offset(100)] AS m100
  FROM rfm_table AS a,
    (SELECT APPROX_QUANTILES(monetary, 100) perc FROM rfm_table) AS m,
    (SELECT APPROX_QUANTILES(frequency, 100) perc FROM rfm_table) AS f,
    (SELECT APPROX_QUANTILES(recency, 100) perc FROM rfm_table) AS r
  GROUP BY ALL
),

score_table AS (
  SELECT *, 
  CONCAT(r_score, f_score, m_score) AS rfm_score,
  ROUND((f_score + m_score) / 2,0) AS fm_score
    FROM (
      SELECT *, 
        CASE WHEN monetary <= m25 THEN 1
        WHEN monetary <= m50 AND monetary > m25 THEN 2 
        WHEN monetary <= m75 AND monetary > m50 THEN 3 
        WHEN monetary <= m100 AND monetary > m75 THEN 4 
      END AS m_score,
      CASE WHEN frequency <= f25 THEN 1
        WHEN frequency <= f50 AND frequency > f25 THEN 2 
        WHEN frequency <= f75 AND frequency > f50 THEN 3 
        WHEN frequency <= f100 AND frequency > f75 THEN 4 
      END AS f_score,
      --Recency scoring is reversed
      CASE WHEN recency <= r25 THEN 4
        WHEN recency <= r50 AND recency > r25 THEN 3
        WHEN recency <= r75 AND recency > r50 THEN 2 
        WHEN recency <= r100 AND recency > r75 THEN 1 
      END AS r_score,
      FROM quantiles_table)
)

#rfm_segments AS (
  SELECT
    CustomerID,
    Country,
    recency,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    rfm_score,
    fm_score,
    CASE WHEN (r_score = 4 AND fm_score = 4) THEN 'Best Customers'
      WHEN (r_score IN (3, 4) AND fm_score IN (3, 4)) THEN 'Loyal Customers'
      WHEN (r_score = 3 AND fm_score = 1) THEN 'Promising Customers'
      WHEN (r_score = 4 AND fm_score = 1) THEN 'New Customers'
      WHEN (r_score IN (3, 4) AND fm_score = 2) THEN 'Potential Loyalist'
      WHEN (r_score = 2 AND fm_score = 3) THEN 'Needs Attention'
      WHEN (r_score = 1 AND fm_score IN (2, 3)) THEN 'At Risk'
      WHEN (r_score IN (1, 2) AND fm_score = 4) THEN 'Cant Lose'
      WHEN (r_score = 1 AND fm_score = 1) THEN 'Lost Customers'
      WHEN (r_score = 2 AND fm_score IN (1, 2)) THEN 'About To Sleep'
      ELSE 'Other Customers'
    END AS rfm_segment
  FROM score_table
)

SELECT rfm_segment,
COUNT(*) AS customer_cnt,
SUM(COUNT(*)) OVER () AS total_customers
FROM rfm_segments
GROUP BY 1
ORDER BY 2 DESC

