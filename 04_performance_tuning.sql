/* 05_performance_tuning.sql
   Purpose : Learn to read execution plans and fix slow queries.
             "Write and optimise complex SQL queries" appears in mid-level
             postings, and this is how you prove it.
   HOW     : 1) In SSMS press Ctrl+M (Include Actual Execution Plan).
             2) Run each section, note logical reads on the Messages tab
                and the plan operators (Table Scan vs Index Seek).
             3) Record before/after numbers in your README.
   ===================================================================== */
*/

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO
 
/* ---------- Experiment 1: filter by date range ---------- */
 
-- 1a. BASELINE: no supporting index, so SQL Server scans the whole table
SELECT customer_id, COUNT(*) AS txns, SUM(amount) AS total_value
FROM   fin.transactions
WHERE  txn_datetime >= '2026-01-01' AND txn_datetime < '2026-02-01'
  AND  status = 'success'
GROUP BY customer_id;
 
-- 1b. Add a covering index (key column + included columns)
CREATE NONCLUSTERED INDEX IX_transactions_datetime
    ON fin.transactions (txn_datetime)
    INCLUDE (customer_id, amount, status);
GO
 
-- 1c. Same query again. Compare logical reads and the plan.
SELECT customer_id, COUNT(*) AS txns, SUM(amount) AS total_value
FROM   fin.transactions
WHERE  txn_datetime >= '2026-01-01' AND txn_datetime < '2026-02-01'
  AND  status = 'success'
GROUP BY customer_id;
 
 
/* ---------- Experiment 2: sargable vs non-sargable filters ---------- */
 
-- 2a. NON-SARGABLE: wrapping the column in functions blocks an index seek
SELECT COUNT(*) AS txns
FROM   fin.transactions
WHERE  YEAR(txn_datetime) = 2026 AND MONTH(txn_datetime) = 1;
 
-- 2b. SARGABLE: a plain range on the column can use the index
SELECT COUNT(*) AS txns
FROM   fin.transactions
WHERE  txn_datetime >= '2026-01-01' AND txn_datetime < '2026-02-01';
-- Question to answer in your README: why do these return the same number but cost very different reads?
 
 
/* ---------- Experiment 3: per-customer lookups ---------- */
 
-- 3a. BASELINE (before the index below)
SELECT txn_datetime, amount, status
FROM   fin.transactions
WHERE  customer_id = 42
ORDER BY txn_datetime;
 
CREATE NONCLUSTERED INDEX IX_transactions_customer
    ON fin.transactions (customer_id, txn_datetime)
    INCLUDE (amount, status);
GO
 
-- 3b. Same query: note the Index Seek and that no separate sort is needed
SELECT txn_datetime, amount, status
FROM   fin.transactions
WHERE  customer_id = 42
ORDER BY txn_datetime;
 
 
/* ---------- Trade-off to discuss ----------
   Every index speeds up reads but slows inserts/updates and uses disk.
   Check what you have:  */
SELECT i.name AS index_name, i.type_desc,
       SUM(ps.used_page_count) * 8 / 1024.0 AS size_mb
FROM   sys.indexes i
JOIN   sys.dm_db_partition_stats ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE  i.object_id = OBJECT_ID('fin.transactions')
GROUP BY i.name, i.type_desc;
 
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
 