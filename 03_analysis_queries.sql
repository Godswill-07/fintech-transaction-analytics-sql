/* =====================================================================
   04_analysis_queries.sql
   Purpose : Eleven business questions answered in T-SQL with inline comments.
   ===================================================================== */
 
USE FintechAnalytics;
GO
 
/* ---------------------------------------------------------------------
   Q1. How is monthly volume and value trending, and what is month-on-month growth?
   Skills: CTE, DATEFROMPARTS, LAG
   --------------------------------------------------------------------- */
WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(txn_datetime), MONTH(txn_datetime), 1) AS month_start, -- Standardizes date to the 1st of every month
           COUNT(*)    AS txn_count,                                               -- Counts total successful transactions
           SUM(amount) AS total_value                                              -- Sums total monetary value for the month
    FROM   fin.transactions
    WHERE  status = 'success'                                                      -- Filters to keep only successful transactions
    GROUP BY DATEFROMPARTS(YEAR(txn_datetime), MONTH(txn_datetime), 1)
)
SELECT month_start,
       txn_count,
       total_value,
       LAG(total_value) OVER (ORDER BY month_start) AS prev_month_value,           -- Grabs the previous month's total value
       CAST(100.0 * (total_value - LAG(total_value) OVER (ORDER BY month_start))   -- Calculates percentage growth from last month safely 
            / NULLIF(LAG(total_value) OVER (ORDER BY month_start), 0) AS DECIMAL(10,2)) AS mom_growth_pct -- (prevents division by zero errors)
FROM   monthly
ORDER BY month_start;                                                             -- Sorts the results chronologically
 
 
/* ---------------------------------------------------------------------
   Q2. Which channels fail the most?
   Skills: conditional aggregation, rate calculation
   --------------------------------------------------------------------- */
SELECT channel,
       COUNT(*) AS total_txns,                                                     -- Total volume of transactions per channel
       SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_txns,          -- Counts only transactions that failed
       CAST(100.0 * SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS failure_rate_pct -- Calculates the failure percentage
FROM   fin.transactions
GROUP BY channel                                                                  -- Groups data by each payment channel
ORDER BY failure_rate_pct DESC;                                                   -- Lists the highest failure rates at the very top


 -- Q3. Who are the top 3 merchants by value in each category?
   -- Skills: JOIN, two CTEs, DENSE_RANK with PARTITION BY
   --------------------------------------------------------------------- */
WITH merchant_totals AS (
    SELECT m.category, -- the m is an alias of fin.merchants, we take the catrgory column
           m.merchant_name, -- we take the merchant_name 
           SUM(t.amount) AS total_value -- the t is an alias of fin.transactions , this line of code takes the sum of all the amount in the amunt column in the fin.transactions 
    FROM   fin.transactions t -- 
    JOIN   fin.merchants    m ON m.merchant_id = t.merchant_id -- this links the merchant table and the transactions table, using the merchant id
    WHERE  t.status = 'success' -- takes only the successful transactions
    GROUP BY m.category, m.merchant_name -- takes the output column which is the totals of amount that has status = scuccess . and group it by merchant_name and category
),
ranked AS ( -- this is the second CTE named "ranked"
    SELECT category, merchant_name, total_value,
           DENSE_RANK() OVER (PARTITION BY category ORDER BY total_value DESC) AS rnk --The DENSE_RANK is a window function, in this code it assigns an integer rank to the rows, and if two merchant have the same totals it assigns the same rank to both PARTITION BY this splits data into groups 
    FROM   merchant_totals -- recalls the CTE
)
SELECT category, merchant_name, total_value, rnk
FROM   ranked
WHERE  rnk <= 3 -- filters to see only the top 3 ranks in each category
ORDER BY category, rnk; -- gives the output only by catgory and rank


/* ---------------------------------------------------------------------
   Q4. Anomaly detection: which days had a failure rate far above normal?
   Skills: window frames (ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING), AVG/STDEV OVER, z-score
   --------------------------------------------------------------------- */
WITH daily AS ( -- the first CTE 
    SELECT CAST(txn_datetime AS DATE) AS txn_date, -- the CAST function strips the time from the txn_datetime and only gives out date 
           COUNT(*) AS total_txns, -- counts all the total transactions (failed) 
           SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_txns -- Take the sum of all the  total failed transactions, gives ouput as 1 for faoled transactions, 
    FROM   fin.transactions
    GROUP BY CAST(txn_datetime AS DATE) -- this groups the output by days 
),
rates AS ( -- second CTE
    SELECT txn_date, total_txns, failed_txns,
           100.0 * failed_txns / total_txns AS fail_pct -- Finds out the failure percentafe daily 
    FROM   daily
),
rolled AS ( -- third CTE
    SELECT *,
           AVG(CAST(fail_pct AS FLOAT))   OVER (ORDER BY txn_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS avg_prev7, -- ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING: This tells SQL to look strictly at the 7 days prior to the current row, excluding the current day itself. This enables us calulate the average failure rate from those 7 days
           STDEV(CAST(fail_pct AS FLOAT)) OVER (ORDER BY txn_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS sd_prev7 -- does the same thing but this calculates the standard deviation
    FROM   rates
)
SELECT txn_date,
       total_txns,
       CAST(fail_pct AS DECIMAL(5,2))  AS fail_pct,
       CAST(avg_prev7 AS DECIMAL(5,2)) AS prev7_avg_pct,
       CAST((fail_pct - avg_prev7) / NULLIF(sd_prev7, 0) AS DECIMAL(6,2)) AS z_score
FROM   rolled
WHERE  (fail_pct - avg_prev7) / NULLIF(sd_prev7, 0) > 3 -- the NULLIF gives a NULL if the sd_prev7 (standard deviation of the seven days is 0), when the WHERE > 3 , thakes only the z score greater than 3
ORDER BY txn_date;
-- Follow-up: for each flagged day, GROUP BY failure_reason to find the cause.

-- Finding the cause of the failures 
-- Follow-up investigation query for question 4  9finding out the reasons for the failures
SELECT t.failure_reason,
       COUNT(*) AS failure_count,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) AS share_of_failures_pct -- the sum is addintg the total count pr failure reason
FROM   fin.transactions t
WHERE  CAST(t.txn_datetime AS DATE) = '2026-03-15' -- Replace with your flagged anomaly date
  AND  t.status = 'failed'
GROUP BY t.failure_reason
ORDER BY failure_count DESC;

-- Q5. Fraud-style velocity check: customers who made 10+ successful transfers
--        within 15 minutes.
--    Skills: LAG with an offset, DATEDIFF, grouping flagged rows
   --------------------------------------------------------------------- */
WITH x AS ( -- first CTE (x)
    SELECT customer_id, txn_id, txn_datetime, amount,
           LAG(txn_datetime, 9) OVER (PARTITION BY customer_id ORDER BY txn_datetime, txn_id) AS ts_9_back -- The LAG and the 9 used checks the previous 9  rows to get the timestamp of the 9th previous transaction
    FROM   fin.transactions
    WHERE  txn_type = 'transfer'
      AND  status = 'success'
)
SELECT customer_id,
       MIN(ts_9_back)    AS burst_start,
       MAX(txn_datetime) AS burst_end,
       COUNT(*)          AS flagged_txns,
       MIN(amount)       AS min_amount,
       MAX(amount)       AS max_amount
FROM   x
WHERE  ts_9_back IS NOT NULL -- Drops rows that don't have at least 9 prior transactions.
  AND  DATEDIFF(MINUTE, ts_9_back, txn_datetime) <= 15 -- Calculates the time elapsed between the 1st transaction (ts_9_back) and the 10th transaction (txn_datetime). If the total cluster happened in 15 minutes or less, it qualifies as a high-velocity "burst."
GROUP BY customer_id
ORDER BY flagged_txns DESC;
-- Follow-up: why are the amounts clustered just under N50,000?

-- Q6. Cohort retention: of customers who signed up in a month, what % transact
 --      in month 0, 1, 2 ... 6 after signup?
  -- Skills: CTEs, DISTINCT, DATEDIFF(MONTH), join to cohort size
   --------------------------------------------------------------------- */
WITH cohort_size AS ( -- first CTE
    SELECT DATEFROMPARTS(YEAR(signup_date), MONTH(signup_date), 1) AS cohort_month, -- Takes the year and month ofsignups from fin.transactions table
           COUNT(*) AS customers
    FROM   fin.customers
    GROUP BY DATEFROMPARTS(YEAR(signup_date), MONTH(signup_date), 1)
),
activity AS (
    SELECT DISTINCT
           t.customer_id,
           DATEFROMPARTS(YEAR(c.signup_date), MONTH(c.signup_date), 1) AS cohort_month,
           DATEDIFF(MONTH,
                    DATEFROMPARTS(YEAR(c.signup_date), MONTH(c.signup_date), 1), 
                    t.txn_datetime) AS month_index -- this checks the year and month the customer that signed up, it then checks the transactions that was made in a MONTH, it also round every transaction's exact timestamp down to the 1st day of its month
    FROM   fin.transactions t
    JOIN   fin.customers    c ON c.customer_id = t.customer_id
    WHERE  t.status = 'success' -- takes only successful transactions
)
SELECT a.cohort_month, -- takes the cohort_month alias from the activity CTE
       cs.customers AS cohort_customers,
       a.month_index, 
       COUNT(DISTINCT a.customer_id) AS active_customers,
       CAST(100.0 * COUNT(DISTINCT a.customer_id) / cs.customers AS DECIMAL(5,2)) AS retention_pct -- calsulate the percentage of customers that are still active
FROM   activity a
JOIN   cohort_size cs ON cs.cohort_month = a.cohort_month -- cs is as an alias for cohort_size, joins the cohort_size CTE and activity CTE due to the common cohort_month alias
WHERE  a.month_index BETWEEN 0 AND 6 -- tracks from month 1 to month 7
GROUP BY a.cohort_month, cs.customers, a.month_index
ORDER BY a.cohort_month, a.month_index;


/* ---------------------------------------------------------------------
   Q10. How much fee revenue does each segment and transaction type generate per month?
   Skills: multi-table JOIN, grouping on two keys, SUM
   --------------------------------------------------------------------- */
SELECT DATEFROMPARTS(YEAR(t.txn_datetime), MONTH(t.txn_datetime), 1) AS month_start, 
       c.segment, -- alias of segment in fin.customers
       t.txn_type, -- alias of txn_type in fin.transactions
       SUM(t.fee)    AS fee_revenue, -- sums all the fee in the fin.transactions
       COUNT(*)      AS txns 
FROM   fin.transactions t
JOIN   fin.customers    c ON c.customer_id = t.customer_id -- join the fin.customers and the fin.transactions because of the unique key (customer_id), the earlier alias c.segment was used because of the JOIN statement, the table has been joined 
WHERE  t.status = 'success'
GROUP BY DATEFROMPARTS(YEAR(t.txn_datetime), MONTH(t.txn_datetime), 1), c.segment, t.txn_type -- to round every transaction's exact timestamp down to the 1st day of its month, so we can see the monthly report 
ORDER BY month_start, c.segment, t.txn_type;


