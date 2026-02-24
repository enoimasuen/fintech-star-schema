--Reload Database
USE fintech_star;
GO

--Analytical Work of the Data (Deliverables)

--Check Approval Rate By Day
SELECT d.full_date,
       SUM(CASE WHEN p.status='approved' THEN 1 ELSE 0 END) AS approved_cnt,
       COUNT(*) AS total_cnt,
       CAST(1.0 * SUM(CASE WHEN p.status='approved' THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0) AS DECIMAL(10,4)) AS approval_rate
FROM dbo.fact_payment p
JOIN dbo.dim_date d ON p.date_id = d.date_id
GROUP BY d.full_date
ORDER BY d.full_date;

--This groups payments by date and calculates how many were approved vs total.
--approved_cnt counts rows where status='approved' 
--total_cnt counts all payments for that date.
--approval_rate = approved_cnt / total_cnt.

--Resulting Data ->
--2026-02-22: approved_cnt=2 out of total_cnt=4, approval_rate=0.50 (50% approved).
--2026-02-23: approved_cnt=2 out of total_cnt=2, approval_rate=1.00 (100% approved).


--Merchant net from payments vs fees
SELECT m.merchant_name,
       SUM(CASE WHEN p.status='approved' THEN p.amount ELSE 0 END) AS gross_approved,
       SUM(ISNULL(f.fee_amount,0)) AS total_fees,
       SUM(CASE WHEN p.status='approved' THEN p.amount ELSE 0 END) - SUM(ISNULL(f.fee_amount,0)) AS net_after_fees
FROM dbo.fact_payment p
JOIN dbo.dim_merchant m ON p.merchant_id = m.merchant_id
LEFT JOIN dbo.fact_fees f ON p.payment_id = f.payment_id
GROUP BY m.merchant_name
ORDER BY net_after_fees DESC;

-- This calculates how much each merchant earned from approved payments, then subtracts fees.
-- gross_approved sums payment amounts only when status='approved'.
-- total_fees sums the fee_amount linked to those payments (ISNULL makes missing fees count as 0).
-- net_after_fees = gross_approved - total_fees
-- Grouping by merchant gives one row per merchant.

--Resulting Data ->
--TechMart: gross_approved=240.00, total_fees=4.80, so net_after_fees=235.20.
--QuickEats: gross_approved=182.00, total_fees=4.20, so net_after_fees=177.80.
--So TechMart netted more after fees in this dataset.

--Decline Reasons
SELECT decline_reason, COUNT(*) AS declined_count
FROM dbo.fact_payment
WHERE status='declined'
GROUP BY decline_reason
ORDER BY declined_count DESC;

--This ooks only at payments that were declined, then groups them by the 'decline_reason'.
--COUNT(*) tells us how many declined payments happened for each reason.
--ORDER BY puts the most common decline reason at the top.

--In this data, there were 2 declined payments because the customer didn’t have enough money.

--Dispute Rate by Merchant
SELECT m.merchant_name,
       COUNT(DISTINCT dis.dispute_id) AS disputes,
       COUNT(DISTINCT p.payment_id) AS payments,
       CAST(1.0 * COUNT(DISTINCT dis.dispute_id) / NULLIF(COUNT(DISTINCT p.payment_id),0) AS DECIMAL(10,4)) AS dispute_rate
FROM dbo.fact_payment p
JOIN dbo.dim_merchant m ON p.merchant_id = m.merchant_id
LEFT JOIN dbo.fact_dispute dis ON dis.payment_id = p.payment_id
GROUP BY m.merchant_name
ORDER BY dispute_rate DESC;

--JOIN payments to merchants so we can measure disputes per merchant.
--LEFT JOIN to disputes keeps merchants/payments even if there are 0 disputes (so I don't lose rows).
--disputes = COUNT(DISTINCT dis.dispute_id)  -> how many unique disputes exist for that merchant's payments
--payments = COUNT(DISTINCT p.payment_id)   -> how many unique payments exist for that merchant
--dispute_rate = disputes / payments
--NULLIF prevents division by zero if a merchant has 0 payments.

--Resulting Data ->
--QuickEats: disputes=1 and payments=4, so dispute_rate = 1/4 = 0.25 (25% of payments were disputed).
--TechMart: disputes=0 and payments=2, so dispute_rate = 0/2 = 0.00 (no disputes).