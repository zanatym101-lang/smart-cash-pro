# AI Project Context - King Wallet Accounting

## Project Identity
This is a production Flutter accounting application for electronic wallets.
It is commercial, already in use, and accounting correctness is more important than speed of development.

The project must be modified with minimal safe changes only.
Do not perform large refactors unless explicitly requested.

---

## Primary Development Policy

This project follows these rules:

1. Do not break accounting balances.
2. Do not modify balances outside the official accounting flow.
3. Do not allow the same operation to be approved twice.
4. Do not break engine rebuild-from-transactions behavior.
5. Always prefer the smallest safe change.
6. Avoid schema changes and migrations unless absolutely necessary.
7. Do not modify critical accounting core without explicit approval.

---

## Critical Areas That Must Not Be Changed Lightly

The following areas are intentionally treated as highly sensitive:

- `lib/accounting/engine.dart`
- `_specFromTxn()`
- `applyEntry()`
- `pending_settlement_adjust` core logic
- `_rebuildEngineFromTxns()`
- core accounting calculation paths

These were intentionally NOT changed in previous work because they are too risky for a live accounting app.

---

## What Was Implemented Recently

### 1. confirmPending() double-approval protection
A protection was added inside `confirmPending()` to prevent the same pending transaction from being approved twice concurrently.

This protects against:
- double approval
- duplicated ledger effects
- duplicated claim creation
- duplicated settlement effects
- incorrect balances

Expected behavior:
- the same `txnId` must not be approved twice during execution
- concurrent approval attempts must result in only one success

---

### 2. Strong tests for confirmPending() protection
Tests were added to prove:
- pending transactions are approved only once
- second approval attempt fails
- financial effect does not repeat
- non-pending transactions cannot be approved

This behavior is not theoretical; it is covered by tests.

---

### 3. fawry_credit safety improvements
Tests were added to ensure:
- `fawry_credit` does not create claim before approval
- after approval exactly one claim is created
- even with concurrency, duplicate claim is prevented

This is a sensitive path with side effects and claims.

---

### 4. claim_collect and claim_pay test hardening
Tests were added to verify:

#### claim_collect
- settles receivable correctly
- increases drawer correctly
- does not accidentally create `claim_pay`

#### claim_pay
- settles payable correctly
- decreases drawer correctly
- does not accidentally create `claim_collect`

---

### 5. Pending settlement test coverage
Safe tests were added for:
- pending settlement in transfer
- pending settlement in receive
- prevention of over-settlement

Important:
The internal `pending_settlement_adjust` core logic itself was NOT changed.
Only its surrounding behavior was analyzed and protected by tests.

---

### 6. confirmPending() audit enrichment
`confirmPending()` audit behavior was improved to store richer approval metadata.
This became the basis for:
- approved_by
- approved_at

without changing the database schema.

---

### 7. Reading approved_by and approved_at
Read helpers were added:

- `getTxnApprovedBy(int txnId)`
- `getTxnApprovedAt(int txnId)`

These values are derived safely from the existing audit structure.

Benefits:
- no schema change
- no migration
- no breaking of old data
- uses existing infrastructure safely

---

### 8. Tests for approved_by and approved_at
Tests were added to verify that after approval we can read:
- who approved the transaction
- when it was approved

---

### 9. UI display of approval metadata
In `tx_details_screen.dart`, transaction details UI now shows:
- approved by
- approved at

when the transaction is approved.

This improves operational transparency.

---

### 10. Transaction reference number
A reference number was added for each transaction in the format:

- `ZA000001`
- `ZA000123`

Implementation detail:
No new DB column was added.
The reference is derived safely from `txn.id`.

Benefits:
- no migration
- no schema change
- no rebuild breakage
- no accounting impact
- simple and safe

---

### 11. Shared helper for transaction reference formatting
Reference formatting was extracted into a shared helper instead of keeping it only inside UI.

This allows reuse in:
- UI
- reports
- search
- exports
- future integrations

---

### 12. Transaction reference shown in UI
`tx_details_screen.dart` now displays:
- transaction reference number

Example:
- `ZA000123`

---

### 13. Copy button for transaction reference
A copy action was added beside the transaction reference in details screen.

Behavior:
- copies reference to clipboard
- shows a confirmation message

Useful for:
- support
- review
- reconciliation
- sharing the reference with another person

---

### 14. Fast safe test for ZA reference helper
Instead of a heavy widget test for the screen, a small fast unit test was added for the reference helper.

It verifies:
- reference starts with `ZA`
- padding is correct

This avoids UI test slowness and timeout.

---

### 15. Isolated race-condition test
A dedicated isolated test file was added for race-condition validation.

It proves:
- `confirmPending()` called twice concurrently succeeds only once
- financial effect does not duplicate

Why isolated:
- to avoid polluting other tests
- to preserve stability of the existing suite

---

### 16. Stable-version-first workflow
During development, unsafe directions were rolled back quickly.
The workflow intentionally preferred:
- returning to last stable version
- then applying a smaller safer change

This is mandatory for a live accounting system.

### 17. Parsing ZA reference into txnId
A shared helper now exists to parse transaction references like `ZA000001`
and `ZA000123` into numeric `txnId` values safely.

Behavior:
- accepts valid `ZA` references
- rejects invalid values safely
- no database impact
- no accounting impact

---

### 18. Search hook for ZA reference in ledger
A small safe hook was added inside the existing ledger search flow.

Behavior:
- if the user enters a `ZA` reference, it is parsed through the helper
- search matches the corresponding `txnId`
- no new screen was added
- no database change was added
- no accounting logic was changed

---

## Things Intentionally Not Changed

For safety, the following were intentionally left unchanged:

- `engine.dart`
- `_specFromTxn()`
- `applyEntry()`
- `pending_settlement_adjust` core accounting logic
- `_rebuildEngineFromTxns()`
- fundamental accounting calculation behavior

Do not change these unless the task explicitly requires it and the risk is analyzed first.

---

## Current Stable Outcome

### Safety
- double approval prevented
- non-pending approval prevented
- claims protected
- `fawry_credit` protected
- pending settlement behavior protected by tests
- race condition protected by isolated test

### Audit / Metadata
- richer approval audit
- `approved_by` readable
- `approved_at` readable

### UI
- transaction reference shown
- approved_by shown
- approved_at shown
- copy button for transaction reference
- ledger search accepts `ZA` reference and direct `txnId`

### Tests
Current stable suite reached:
- `106 tests passed`

---

## AI Operating Rules For This Project

When working on this project:

1. Read only the directly relevant files first.
2. Do not scan the whole project unless explicitly requested.
3. Do not refactor large areas.
4. Do not rewrite working accounting code.
5. Prefer additive changes and minimal edits.
6. Keep compatibility with current production data.
7. Use tests to protect behavior instead of changing sensitive internals.
8. If a requested change touches accounting core, explain risk before editing.
9. If a requested change touches approval, claims, settlement, or audit, be extra conservative.
10. If a change can be implemented through helper, audit, UI, or test coverage instead of core accounting logic, prefer that route.

---

## Recommended AI Workflow

Before editing:
1. Summarize the request briefly.
2. List only the files that need reading.
3. Identify the risk.
4. Propose the smallest safe change.

During editing:
1. Modify only the necessary files.
2. Keep names, schema, and transaction flow stable.
3. Avoid hidden side effects.

After editing:
1. Summarize exactly what changed.
2. Mention what was intentionally left untouched.
3. Provide a manual test checklist.
4. Suggest a commit message.

---

## High-Risk Business Concepts

The AI must treat these as high-risk:
- balances
- approvals
- claims
- settlements
- drawer effects
- engine rebuild consistency
- duplicate financial side effects

If a task could affect one of these, stop and analyze before coding.

---

## Preferred Strategy For Future Changes

Priority order:
1. Small helper
2. Small UI addition
3. Read-only metadata extraction
4. Narrow test coverage
5. Minimal isolated business change
6. Core accounting change only if unavoidable

---

## Short Summary
This is a live accounting Flutter application.
Recent work focused on:
- preventing duplicate pending approval
- strengthening tests around claims and settlements
- enriching approval audit metadata
- exposing approval metadata in UI
- adding safe transaction reference numbers
- preserving stability without touching accounting core
---

## Implementation Status (Very Important)

### Implemented (Already Done in Code)

The following features are already implemented and exist in the codebase:

- transaction reference display in UI (ZAxxxxxx)
- copy button for transaction reference
- `txnIdFromReference(String reference)` helper
- tests for `txnIdFromReference(...)`
- ledger search hook using ZA reference -> txnId
- approval metadata (approved_by, approved_at)
- confirmPending() protection against double approval
- test coverage for approval, claims, and settlement
- isolated race-condition test
- stable accounting behavior without modifying engine core

---

### Planned But NOT Implemented Yet

The following ideas were discussed but are NOT implemented in the codebase:

- search for transactions (txns)
- advanced filtering for transactions

Important:
Do NOT assume these features exist.
They must be implemented from scratch when requested.

---

## Rule For AI

Never assume that a discussed idea is already implemented.

Only rely on:
- actual code
- explicitly confirmed implemented features

If unsure:
ask before proceeding.
