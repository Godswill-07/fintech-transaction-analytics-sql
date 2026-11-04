-- importing the data into the tables using Import Data Wizard

select * from fin.customers -- to check
select * from fin.merchants
select * from fin.transactions

/*
Data Quality checks: To validate the data before analyzing
*/

USE FintechAnalytics; -- switches the working database to this 
GO
 
-- 1. Row counts and date range
SELECT COUNT(*)            AS total_rows, --- counts every single row in the table and labels the column as total_rows
       MIN(txn_datetime)   AS first_txn, 
       MAX(txn_datetime)   AS last_txn,
       COUNT(DISTINCT customer_id) AS active_customers -- counts how manny unique customers appear in the transactions table
FROM   fin.transactions; -- tells sql server to calculate the metrics above sing the fin.transactions

-- 2. Duplicate transaction IDs (PK should prevent them, but prove it) we want to stop duplicates in the transactons table
SELECT txn_id, COUNT(*) AS copies -- look at each txn_id and count how many times they occur
FROM   fin.transactions
GROUP BY txn_id -- groups all rows together by unique transaction ID
HAVING COUNT(*) > 1; -- filter it and give out the one that has count above 1

-- The output shows that there are no copies 

-- 3. Transactions dated before the customer signed up
SELECT COUNT(*) AS txns_before_signup -- counts all the rows that falls into the WHERE CONDITION
FROM   fin.transactions t
JOIN   fin.customers   c ON c.customer_id = t.customer_id -- joins the transaction table and the customer table using customer id
WHERE  CAST(t.txn_datetime AS DATE) < c.signup_date; -- t is an alias of fin.transactions and c is an alias of fin.customers , so the CAST(t.txn_datetime AS DATE) < c.signup_date
-- first strips the datetime column from its time and changes it to date, it then counts every transaction date that was before the customer sign up date

-- Zero transactions were found

-- 4. Failed or reversed transactions that still carry a fee (should be zero)
SELECT COUNT(*) AS non_success_with_fee -- counts all the rows that falls under the metric below in the where condition and labels the column as non_success_with_fee
FROM   fin.transactions
WHERE  status <> 'success' AND fee > 0; -- this checks whether the status is not equal to (<>) success and the fee was a positive value]

-- Output - Zero was gotten

-- 5. Merchant-linked types missing a merchant, and non-merchant types with one
SELECT txn_type,
       SUM(CASE WHEN merchant_id IS NULL     THEN 1 ELSE 0 END) AS missing_merchant, -- using a CASE inside a SUM, if the merchant_id is NULL return 1 else 0 (meaning this has no merchant -  peer to peer tansfer/ airitme).
       SUM(CASE WHEN merchant_id IS NOT NULL THEN 1 ELSE 0 END) AS has_merchant -- using a CASE inside a SUM, if the merchant_id is NOT  NULL return 0 else 1 meaning this has merchant
FROM   fin.transactions
GROUP BY txn_type -- groups the count and UMS of each distinct transaction type
ORDER BY txn_type;


-- The sum also sums all the merchant that falls under each rule


-- 6. Failed transactions without a reason, successful ones with a reason
SELECT status,
       SUM(CASE WHEN failure_reason IS NULL THEN 1 ELSE 0 END) AS null_reason, -- if the failure reason is null then the output is 1 else 0, its counted, the total sum of all cases that is null is taken
       SUM(CASE WHEN failure_reason IS NOT NULL THEN 1 ELSE 0 END) AS has_reason  -- if the failure reason is not null then the output is 1 else 0, its counted, the total sum of all cases that is not null is taken
FROM   fin.transactions
GROUP BY status; -- this groups all the status (sucess, failed, reversed)

-- all status of transactions had a reason

-- 7. Status mix (sanity check on overall failure rate)
SELECT status,
       COUNT(*) AS txns, -- this does group counting of each group of status and saves the column as txns
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct  -- the Count(*) is group count, OVER() counts every row it ignores the groupings, then the count(*) / SUM(COUNT(*) divides the specific group count by the total number of counts, the division is then multiplied by 100 for integer devision 
FROM   fin.transactions
GROUP BY status;

-- e.g (100* 942) / 1000
 
-- 8. Amount outliers: the 10 largest successful transactions
SELECT TOP (10) txn_id, customer_id, txn_type, channel, amount, txn_datetime
FROM   fin.transactions
WHERE  status = 'success'
ORDER BY amount DESC;

-- This is for getting the TOP 10 largest successful transactions

