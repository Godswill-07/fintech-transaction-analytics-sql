/* =====================================================================
   01_create_schema.sql
   Project : Fintech Transaction Analytics (SQL Server / T-SQL)
   Purpose : Create the database, schema and three tables.
   Target  : SQL Server 2016 or newer, run in SSMS.
   ===================================================================== */
 
IF DB_ID('FintechAnalytics') IS NULL
    CREATE DATABASE FintechAnalytics;
GO
 
-- Simple recovery keeps the log small while we bulk-load on a laptop
ALTER DATABASE FintechAnalytics SET RECOVERY SIMPLE;
GO
 
USE FintechAnalytics;
GO
 
IF SCHEMA_ID('fin') IS NULL
    EXEC('CREATE SCHEMA fin');
GO
 
-- Drop in dependency order so the script can be re-run safely
DROP TABLE IF EXISTS fin.transactions;
DROP TABLE IF EXISTS fin.merchants;
DROP TABLE IF EXISTS fin.customers;
GO
 
CREATE TABLE fin.customers (
    customer_id  INT          NOT NULL CONSTRAINT PK_customers PRIMARY KEY,
    signup_date  DATE         NOT NULL,
    state        NVARCHAR(30) NOT NULL,
    segment      NVARCHAR(10) NOT NULL CONSTRAINT CK_customers_segment CHECK (segment IN ('Retail', 'SME')),
    kyc_tier     TINYINT      NOT NULL CONSTRAINT CK_customers_kyc CHECK (kyc_tier BETWEEN 1 AND 3)
);
 
CREATE TABLE fin.merchants (
    merchant_id    INT          NOT NULL CONSTRAINT PK_merchants PRIMARY KEY,
    merchant_name  NVARCHAR(60) NOT NULL,
    category       NVARCHAR(30) NOT NULL,
    state          NVARCHAR(30) NOT NULL
);
 
CREATE TABLE fin.transactions (
    txn_id          BIGINT        NOT NULL CONSTRAINT PK_transactions PRIMARY KEY,
    customer_id     INT           NOT NULL CONSTRAINT FK_txn_customer REFERENCES fin.customers (customer_id),
    merchant_id     INT           NULL     CONSTRAINT FK_txn_merchant REFERENCES fin.merchants (merchant_id),
    txn_datetime    DATETIME2(0)  NOT NULL,
    txn_type        NVARCHAR(20)  NOT NULL,   -- transfer, airtime, bill_payment, pos, cash_in, withdrawal
    channel         NVARCHAR(20)  NOT NULL,   -- mobile_app, ussd, web, pos, atm
    amount          DECIMAL(18,2) NOT NULL CONSTRAINT CK_txn_amount CHECK (amount > 0),
    fee             DECIMAL(18,2) NOT NULL,
    status          NVARCHAR(10)  NOT NULL CONSTRAINT CK_txn_status CHECK (status IN ('success', 'failed', 'reversed')),
    failure_reason  NVARCHAR(40)  NULL
);
GO