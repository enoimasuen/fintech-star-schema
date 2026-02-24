USE fintech_star;
GO

--Timestamp + merge, foreign key-safe 

IF OBJECT_ID('dbo.etl_watermark', 'U') IS NOT NULL DROP TABLE dbo.etl_watermark;
GO
CREATE TABLE dbo.etl_watermark (
    process_name VARCHAR(50) NOT NULL PRIMARY KEY,
    last_run_at   DATETIME2(0) NULL
);
GO
INSERT INTO dbo.etl_watermark(process_name, last_run_at)
VALUES ('payment_etl', NULL), ('fees_etl', NULL);
GO

IF OBJECT_ID('dbo.stg_payment', 'U') IS NOT NULL DROP TABLE dbo.stg_payment;
GO
CREATE TABLE dbo.stg_payment (
    payment_reference VARCHAR(80) NOT NULL,
    date_id INT NOT NULL,
    customer_id BIGINT NOT NULL,
    merchant_id BIGINT NOT NULL,
    wallet_id BIGINT NOT NULL,
    payment_method_id INT NOT NULL,
    currency_id SMALLINT NOT NULL,
    amount DECIMAL(14,2) NOT NULL,
    status VARCHAR(20) NOT NULL,
    decline_reason VARCHAR(80) NULL,
    is_refund BIT NOT NULL DEFAULT 0,
    last_updated DATETIME2(0) NOT NULL,
    is_deleted BIT NOT NULL DEFAULT 0,
    CONSTRAINT pk_stg_payment PRIMARY KEY (payment_reference)
);
GO

IF OBJECT_ID('dbo.stg_fees', 'U') IS NOT NULL DROP TABLE dbo.stg_fees;
GO
CREATE TABLE dbo.stg_fees (
    payment_reference VARCHAR(80) NOT NULL,
    date_id INT NOT NULL,
    fee_type VARCHAR(30) NOT NULL,
    fee_amount DECIMAL(14,2) NOT NULL,
    last_updated DATETIME2(0) NOT NULL,
    is_deleted BIT NOT NULL DEFAULT 0,
    CONSTRAINT pk_stg_fees PRIMARY KEY (payment_reference, fee_type)
);
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'ux_fact_payment_reference'
      AND object_id = OBJECT_ID('dbo.fact_payment')
)
BEGIN
    CREATE UNIQUE INDEX ux_fact_payment_reference
    ON dbo.fact_payment(reference)
    WHERE reference IS NOT NULL;
END
GO

USE fintech_star;
GO

--Payment ETL proc (merge + delete using when and then)

IF OBJECT_ID('dbo.usp_etl_load_fact_payment', 'P') IS NOT NULL
    DROP PROC dbo.usp_etl_load_fact_payment;
GO

CREATE PROC dbo.usp_etl_load_fact_payment
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @last_run DATETIME2(0);
    SELECT @last_run = last_run_at
    FROM dbo.etl_watermark
    WHERE process_name = 'payment_etl';

    IF @last_run IS NULL SET @last_run = '1900-01-01';

    MERGE dbo.fact_payment AS T
    USING (
        SELECT *
        FROM dbo.stg_payment
        WHERE last_updated > @last_run
    ) AS S
      ON (T.reference = S.payment_reference)

    WHEN MATCHED THEN
        UPDATE SET
            T.date_id = S.date_id,
            T.customer_id = S.customer_id,
            T.merchant_id = S.merchant_id,
            T.wallet_id = S.wallet_id,
            T.payment_method_id = S.payment_method_id,
            T.currency_id = S.currency_id,
            T.amount = S.amount,
            T.decline_reason = S.decline_reason,
            T.is_refund = S.is_refund,
            T.status = CASE WHEN S.is_deleted = 1 THEN 'reversed' ELSE S.status END,
            T.is_deleted = S.is_deleted

    WHEN NOT MATCHED BY TARGET AND S.is_deleted = 0 THEN
        INSERT (date_id, customer_id, merchant_id, wallet_id, payment_method_id, currency_id,
                amount, status, decline_reason, is_refund, reference, is_deleted)
        VALUES (S.date_id, S.customer_id, S.merchant_id, S.wallet_id, S.payment_method_id, S.currency_id,
                S.amount, S.status, S.decline_reason, S.is_refund, S.payment_reference, 0)
    ;

    -- set time stamps
    DECLARE @new_last_run DATETIME2(0);
    SELECT @new_last_run = MAX(last_updated)
    FROM dbo.stg_payment
    WHERE last_updated > @last_run;

    UPDATE dbo.etl_watermark
    SET last_run_at = COALESCE(@new_last_run, last_run_at)
    WHERE process_name = 'payment_etl';
END
GO

USE fintech_star;
GO

--Fees ETL proc (merge)

IF OBJECT_ID('dbo.usp_etl_load_fact_fees', 'P') IS NOT NULL
    DROP PROC dbo.usp_etl_load_fact_fees;
GO

CREATE PROC dbo.usp_etl_load_fact_fees
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @last_run DATETIME2(0);
    SELECT @last_run = last_run_at
    FROM dbo.etl_watermark
    WHERE process_name = 'fees_etl';

    IF @last_run IS NULL SET @last_run = '1900-01-01';

    MERGE dbo.fact_fees AS T
    USING (
        SELECT
            fp.payment_id,
            sf.date_id,
            sf.fee_type,
            sf.fee_amount,
            sf.is_deleted,
            sf.last_updated
        FROM dbo.stg_fees sf
        JOIN dbo.fact_payment fp
          ON fp.reference = sf.payment_reference
        WHERE sf.last_updated > @last_run
          AND fp.is_deleted = 0
    ) AS S
      ON (T.payment_id = S.payment_id AND T.fee_type = S.fee_type)

    WHEN MATCHED AND S.is_deleted = 0 THEN
        UPDATE SET
            T.date_id = S.date_id,
            T.fee_amount = S.fee_amount

    WHEN NOT MATCHED BY TARGET AND S.is_deleted = 0 THEN
        INSERT (payment_id, date_id, fee_type, fee_amount)
        VALUES (S.payment_id, S.date_id, S.fee_type, S.fee_amount)

    WHEN MATCHED AND S.is_deleted = 1 THEN
        DELETE
    ; 

    DECLARE @new_last_run DATETIME2(0);
    SELECT @new_last_run = MAX(last_updated)
    FROM dbo.stg_fees
    WHERE last_updated > @last_run;

    UPDATE dbo.etl_watermark
    SET last_run_at = COALESCE(@new_last_run, last_run_at)
    WHERE process_name = 'fees_etl';
END
GO

USE fintech_star;
GO

--Staging inserts + run ETL

TRUNCATE TABLE dbo.stg_fees;
TRUNCATE TABLE dbo.stg_payment;
GO

INSERT INTO dbo.stg_payment
(payment_reference, date_id, customer_id, merchant_id, wallet_id, payment_method_id, currency_id,
 amount, status, decline_reason, is_refund, last_updated, is_deleted)
VALUES
('PAY-100', 20260222, 1, 1, 1, 1, 1, 45.50, 'approved', NULL, 0, '2026-02-23 10:00:00', 0),
('PAY-101', 20260222, 2, 1, 2, 1, 1, 60.00, 'declined', 'insufficient_funds', 0, '2026-02-23 10:00:00', 0),
('PAY-102', 20260223, 1, 2, 1, 1, 1, 120.00,'approved', NULL, 0, '2026-02-23 10:00:00', 0);

INSERT INTO dbo.stg_fees
(payment_reference, date_id, fee_type, fee_amount, last_updated, is_deleted)
VALUES
('PAY-100', 20260222, 'platform', 1.25, '2026-02-23 10:00:00', 0),
('PAY-100', 20260222, 'interchange', 0.85, '2026-02-23 10:00:00', 0),
('PAY-102', 20260223, 'platform', 2.40, '2026-02-23 10:00:00', 0);
GO

EXEC dbo.usp_etl_load_fact_payment;
EXEC dbo.usp_etl_load_fact_fees;
GO

SELECT * FROM dbo.fact_payment ORDER BY payment_id;
SELECT * FROM dbo.fact_fees ORDER BY fee_id;
SELECT * FROM dbo.etl_watermark;
GO

USE fintech_star;
GO

--Validation Checksum Point

WITH src AS (
    SELECT
        payment_reference,
        CHECKSUM(payment_reference, date_id, customer_id, merchant_id, wallet_id, payment_method_id, currency_id,
                 amount, status, ISNULL(decline_reason,''), is_refund) AS src_hash
    FROM dbo.stg_payment
    WHERE is_deleted = 0
),
tgt AS (
    SELECT
        reference AS payment_reference,
        CHECKSUM(reference, date_id, customer_id, merchant_id, wallet_id, payment_method_id, currency_id,
                 amount, status, ISNULL(decline_reason,''), is_refund) AS tgt_hash
    FROM dbo.fact_payment
    WHERE is_deleted = 0
)
SELECT
    COALESCE(s.payment_reference, t.payment_reference) AS payment_reference,
    s.src_hash,
    t.tgt_hash,
    CASE
        WHEN s.payment_reference IS NULL THEN 'MISSING_IN_SOURCE'
        WHEN t.payment_reference IS NULL THEN 'MISSING_IN_TARGET'
        WHEN s.src_hash <> t.tgt_hash THEN 'MISMATCH'
        ELSE 'OK'
    END AS validation_result
FROM src s
FULL OUTER JOIN tgt t
  ON s.payment_reference = t.payment_reference
ORDER BY validation_result, payment_reference;

--STAGE 3 MODEL IS COMPLETE (has history and is simplified)