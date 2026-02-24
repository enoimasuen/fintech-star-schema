--Fintech Star Model (Payments + Wallets)

--Create DB if it doesn't exist
IF DB_ID('fintech_star') IS NULL
BEGIN
    CREATE DATABASE fintech_star;
END
GO

USE fintech_star;
GO

--DIMENSIONS

IF OBJECT_ID('dbo.dim_date', 'U') IS NOT NULL DROP TABLE dbo.dim_date;
GO
CREATE TABLE dbo.dim_date (
  date_id INT NOT NULL PRIMARY KEY,      
  full_date DATE NOT NULL,
  [day] TINYINT NOT NULL,
  [month] TINYINT NOT NULL,
  [quarter] TINYINT NOT NULL,
  [year] SMALLINT NOT NULL
);
GO

IF OBJECT_ID('dbo.dim_country', 'U') IS NOT NULL DROP TABLE dbo.dim_country;
GO
CREATE TABLE dbo.dim_country (
  country_id SMALLINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  country_code CHAR(2) NOT NULL UNIQUE,
  country_name VARCHAR(80) NOT NULL
);
GO

IF OBJECT_ID('dbo.dim_currency', 'U') IS NOT NULL DROP TABLE dbo.dim_currency;
GO
CREATE TABLE dbo.dim_currency (
  currency_id SMALLINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  currency_code CHAR(3) NOT NULL UNIQUE
);
GO

IF OBJECT_ID('dbo.dim_payment_method', 'U') IS NOT NULL DROP TABLE dbo.dim_payment_method;
GO
CREATE TABLE dbo.dim_payment_method (
  payment_method_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  payment_method VARCHAR(40) NOT NULL UNIQUE   --card/ach/wallet/bank_transfer
);
GO

IF OBJECT_ID('dbo.dim_customer', 'U') IS NOT NULL DROP TABLE dbo.dim_customer;
GO
CREATE TABLE dbo.dim_customer (
  customer_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  customer_type VARCHAR(20) NOT NULL,          --consumer/business
  created_date_id INT NOT NULL,
  kyc_level VARCHAR(20) NOT NULL,              --none/basic/full
  kyc_status VARCHAR(20) NOT NULL,             --pending/approved/rejected
  is_active BIT NOT NULL DEFAULT 1,
  country_id SMALLINT NOT NULL,

  CONSTRAINT fk_customer_created_date
    FOREIGN KEY (created_date_id) REFERENCES dbo.dim_date(date_id),

  CONSTRAINT fk_customer_country
    FOREIGN KEY (country_id) REFERENCES dbo.dim_country(country_id)
);
GO

IF OBJECT_ID('dbo.dim_merchant', 'U') IS NOT NULL DROP TABLE dbo.dim_merchant;
GO
CREATE TABLE dbo.dim_merchant (
  merchant_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  merchant_name VARCHAR(120) NOT NULL,
  industry VARCHAR(60) NULL,
  onboarding_status VARCHAR(20) NOT NULL,      --pending/approved/rejected
  risk_tier VARCHAR(20) NOT NULL,              --low/med/high
  country_id SMALLINT NOT NULL,

  CONSTRAINT fk_merchant_country
    FOREIGN KEY (country_id) REFERENCES dbo.dim_country(country_id)
);
GO

IF OBJECT_ID('dbo.dim_wallet', 'U') IS NOT NULL DROP TABLE dbo.dim_wallet;
GO
CREATE TABLE dbo.dim_wallet (
  wallet_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  customer_id BIGINT NOT NULL,
  currency_id SMALLINT NOT NULL,
  opened_date_id INT NOT NULL,
  wallet_status VARCHAR(20) NOT NULL,          --active/frozen/closed

  CONSTRAINT fk_wallet_customer
    FOREIGN KEY (customer_id) REFERENCES dbo.dim_customer(customer_id),

  CONSTRAINT fk_wallet_currency
    FOREIGN KEY (currency_id) REFERENCES dbo.dim_currency(currency_id),

  CONSTRAINT fk_wallet_opened_date
    FOREIGN KEY (opened_date_id) REFERENCES dbo.dim_date(date_id)
);
GO

--FACTS

IF OBJECT_ID('dbo.fact_payment', 'U') IS NOT NULL DROP TABLE dbo.fact_payment;
GO
CREATE TABLE dbo.fact_payment (
  payment_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  date_id INT NOT NULL,
  customer_id BIGINT NOT NULL,
  merchant_id BIGINT NOT NULL,
  wallet_id BIGINT NOT NULL,
  payment_method_id INT NOT NULL,
  currency_id SMALLINT NOT NULL,

  amount DECIMAL(14,2) NOT NULL,
  status VARCHAR(20) NOT NULL,                 --approved/declined/reversed
  decline_reason VARCHAR(80) NULL,
  is_refund BIT NOT NULL DEFAULT 0,
  reference VARCHAR(80) NULL,

  CONSTRAINT fk_payment_date
    FOREIGN KEY (date_id) REFERENCES dbo.dim_date(date_id),

  CONSTRAINT fk_payment_customer
    FOREIGN KEY (customer_id) REFERENCES dbo.dim_customer(customer_id),

  CONSTRAINT fk_payment_merchant
    FOREIGN KEY (merchant_id) REFERENCES dbo.dim_merchant(merchant_id),

  CONSTRAINT fk_payment_wallet
    FOREIGN KEY (wallet_id) REFERENCES dbo.dim_wallet(wallet_id),

  CONSTRAINT fk_payment_method
    FOREIGN KEY (payment_method_id) REFERENCES dbo.dim_payment_method(payment_method_id),

  CONSTRAINT fk_payment_currency
    FOREIGN KEY (currency_id) REFERENCES dbo.dim_currency(currency_id)
);
GO

CREATE INDEX idx_payment_date ON dbo.fact_payment(date_id);
CREATE INDEX idx_payment_customer_date ON dbo.fact_payment(customer_id, date_id);
CREATE INDEX idx_payment_merchant_date ON dbo.fact_payment(merchant_id, date_id);
GO

IF OBJECT_ID('dbo.fact_fees', 'U') IS NOT NULL DROP TABLE dbo.fact_fees;
GO
CREATE TABLE dbo.fact_fees (
  fee_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  payment_id BIGINT NOT NULL,
  date_id INT NOT NULL,
  fee_type VARCHAR(30) NOT NULL,
  fee_amount DECIMAL(14,2) NOT NULL,

  CONSTRAINT fk_fees_payment
    FOREIGN KEY (payment_id) REFERENCES dbo.fact_payment(payment_id),

  CONSTRAINT fk_fees_date
    FOREIGN KEY (date_id) REFERENCES dbo.dim_date(date_id)
);
GO

CREATE INDEX idx_fees_payment ON dbo.fact_fees(payment_id);
CREATE INDEX idx_fees_date ON dbo.fact_fees(date_id);
GO

IF OBJECT_ID('dbo.fact_settlement', 'U') IS NOT NULL DROP TABLE dbo.fact_settlement;
GO
CREATE TABLE dbo.fact_settlement (
  settlement_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  date_id INT NOT NULL,
  merchant_id BIGINT NOT NULL,
  currency_id SMALLINT NOT NULL,

  gross_amount DECIMAL(14,2) NOT NULL,
  total_fees DECIMAL(14,2) NOT NULL,
  net_amount DECIMAL(14,2) NOT NULL,

  settlement_status VARCHAR(20) NOT NULL,
  settlement_reference VARCHAR(80) NULL,

  CONSTRAINT fk_settlement_date
    FOREIGN KEY (date_id) REFERENCES dbo.dim_date(date_id),

  CONSTRAINT fk_settlement_merchant
    FOREIGN KEY (merchant_id) REFERENCES dbo.dim_merchant(merchant_id),

  CONSTRAINT fk_settlement_currency
    FOREIGN KEY (currency_id) REFERENCES dbo.dim_currency(currency_id)
);
GO

CREATE INDEX idx_settlement_merchant_date ON dbo.fact_settlement(merchant_id, date_id);
GO

IF OBJECT_ID('dbo.fact_dispute', 'U') IS NOT NULL DROP TABLE dbo.fact_dispute;
GO
CREATE TABLE dbo.fact_dispute (
  dispute_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  payment_id BIGINT NOT NULL,
  opened_date_id INT NOT NULL,
  closed_date_id INT NULL,

  dispute_type VARCHAR(30) NOT NULL,
  dispute_status VARCHAR(20) NOT NULL,
  dispute_amount DECIMAL(14,2) NOT NULL,

  CONSTRAINT fk_dispute_payment
    FOREIGN KEY (payment_id) REFERENCES dbo.fact_payment(payment_id),

  CONSTRAINT fk_dispute_opened_date
    FOREIGN KEY (opened_date_id) REFERENCES dbo.dim_date(date_id),

  CONSTRAINT fk_dispute_closed_date
    FOREIGN KEY (closed_date_id) REFERENCES dbo.dim_date(date_id)
);
GO

CREATE INDEX idx_dispute_payment ON dbo.fact_dispute(payment_id);
CREATE INDEX idx_dispute_status ON dbo.fact_dispute(dispute_status);
GO

IF OBJECT_ID('dbo.fact_wallet_balance_daily', 'U') IS NOT NULL DROP TABLE dbo.fact_wallet_balance_daily;
GO
CREATE TABLE dbo.fact_wallet_balance_daily (
  wallet_id BIGINT NOT NULL,
  date_id INT NOT NULL,
  ending_balance DECIMAL(14,2) NOT NULL,
  available_balance DECIMAL(14,2) NOT NULL,

  CONSTRAINT pk_wallet_balance PRIMARY KEY (wallet_id, date_id),

  CONSTRAINT fk_balance_wallet
    FOREIGN KEY (wallet_id) REFERENCES dbo.dim_wallet(wallet_id),

  CONSTRAINT fk_balance_date
    FOREIGN KEY (date_id) REFERENCES dbo.dim_date(date_id)
);
GO

IF OBJECT_ID('dbo.fact_transfer', 'U') IS NOT NULL DROP TABLE dbo.fact_transfer;
GO
CREATE TABLE dbo.fact_transfer (
  transfer_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  date_id INT NOT NULL,
  from_wallet_id BIGINT NOT NULL,
  to_wallet_id BIGINT NOT NULL,
  currency_id SMALLINT NOT NULL,

  amount DECIMAL(14,2) NOT NULL,
  transfer_type VARCHAR(30) NOT NULL,          --p2p/withdrawal/deposit
  status VARCHAR(20) NOT NULL,                 --completed/pending/failed
  reference VARCHAR(80) NULL,

  CONSTRAINT fk_transfer_date
    FOREIGN KEY (date_id) REFERENCES dbo.dim_date(date_id),

  CONSTRAINT fk_transfer_from_wallet
    FOREIGN KEY (from_wallet_id) REFERENCES dbo.dim_wallet(wallet_id),

  CONSTRAINT fk_transfer_to_wallet
    FOREIGN KEY (to_wallet_id) REFERENCES dbo.dim_wallet(wallet_id),

  CONSTRAINT fk_transfer_currency
    FOREIGN KEY (currency_id) REFERENCES dbo.dim_currency(currency_id)
);
GO

CREATE INDEX idx_transfer_date ON dbo.fact_transfer(date_id);
CREATE INDEX idx_transfer_from_wallet ON dbo.fact_transfer(from_wallet_id);
CREATE INDEX idx_transfer_to_wallet ON dbo.fact_transfer(to_wallet_id);
GO

--Data Modeling For Inputs

INSERT INTO dim_date (date_id, full_date, [day], [month], [quarter], [year]) VALUES
(20260221, '2026-02-21', 21, 2, 1, 2026),
(20260222, '2026-02-22', 22, 2, 1, 2026),
(20260223, '2026-02-23', 23, 2, 1, 2026);

INSERT INTO dim_country (country_code, country_name) VALUES
('US', 'United States'),
('NG', 'Nigeria');

INSERT INTO dim_currency (currency_code) VALUES
('USD');

INSERT INTO dim_payment_method (payment_method) VALUES
('card'),
('wallet'),
('bank_transfer');

INSERT INTO dim_customer
(customer_type, created_date_id, kyc_level, kyc_status, is_active, country_id)
VALUES
('consumer', 20260221, 'full', 'approved', 1, 1),
('consumer', 20260221, 'basic', 'pending', 1, 2);

INSERT INTO dim_merchant
(merchant_name, industry, onboarding_status, risk_tier, country_id)
VALUES
('QuickEats', 'food_delivery', 'approved', 'medium', 1),
('TechMart', 'ecommerce', 'approved', 'low', 1);

INSERT INTO dim_wallet
(customer_id, currency_id, opened_date_id, wallet_status)
VALUES
(1, 1, 20260221, 'active'),
(2, 1, 20260221, 'active');

INSERT INTO fact_payment
(date_id, customer_id, merchant_id, wallet_id, payment_method_id, currency_id,
 amount, status, decline_reason, is_refund, reference)
VALUES
(20260222, 1, 1, 1, 1, 1, 45.50, 'approved', NULL, 0, 'PAY-001'),
(20260222, 2, 1, 2, 1, 1, 60.00, 'declined', 'insufficient_funds', 0, 'PAY-002'),
(20260223, 1, 2, 1, 1, 1, 120.00, 'approved', NULL, 0, 'PAY-003');

INSERT INTO fact_fees
(payment_id, date_id, fee_type, fee_amount)
VALUES
(1, 20260222, 'platform', 1.25),
(1, 20260222, 'interchange', 0.85),
(3, 20260223, 'platform', 2.40);

INSERT INTO fact_settlement
(date_id, merchant_id, currency_id, gross_amount, total_fees, net_amount,
 settlement_status, settlement_reference)
VALUES
(20260223, 1, 1, 45.50, 2.10, 43.40, 'paid', 'SET-QE-20260223'),
(20260223, 2, 1, 120.00, 2.40, 117.60, 'paid', 'SET-TM-20260223');

INSERT INTO fact_dispute
(payment_id, opened_date_id, closed_date_id, dispute_type, dispute_status, dispute_amount)
VALUES
(1, 20260223, NULL, 'dispute', 'open', 45.50);

INSERT INTO fact_wallet_balance_daily
(wallet_id, date_id, ending_balance, available_balance)
VALUES
(1, 20260221, 200.00, 200.00),
(1, 20260222, 154.50, 154.50),
(1, 20260223, 34.50, 34.50),
(2, 20260222, 10.00, 10.00);

INSERT INTO fact_transfer
(date_id, from_wallet_id, to_wallet_id, currency_id,
 amount, transfer_type, status, reference)
VALUES
(20260222, 1, 2, 1, 25.00, 'p2p', 'completed', 'TX-001');