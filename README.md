# fintech-star-schema
A model that represents the lifecycle of money inside a digital wallet fintech platform — from payment initiation to settlement, fees, disputes, and balance tracking

# Fintech Star Schema (Payments + Wallets)

## Overview
This project models a fintech digital wallet and payment platform using a star schema design.

It captures the lifecycle of transactions including:
- Payments
- Transfers
- Fees
- Settlements
- Disputes
- Daily wallet balances

## Schema Design

### Dimensions
- dim_customer (KYC level, risk tier, onboarding status)
- dim_wallet
- dim_merchant
- dim_date
- dim_currency
- dim_country

### Fact Tables
- fact_payment
- fact_transfer
- fact_fees
- fact_settlement
- fact_dispute
- fact_wallet_balance_daily

## Example Analytics Queries

- Approval rate by date
- Dispute rate by merchant
- Net revenue after fees by merchant
- Decline reason distribution

## Business Purpose

This schema supports fintech analytics use cases such as:
- Revenue tracking
- Fraud monitoring
- Merchant risk analysis
- Operational performance reporting
