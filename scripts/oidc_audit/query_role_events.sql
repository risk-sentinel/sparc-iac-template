-- 30-day permission audit query for sparc-iac-github-actions OIDC role.
-- Returns unique (eventSource, eventName) pairs with frequency + timestamps,
-- scoped to the last 30 days for the role's assumed-role sessions.
--
-- Used by: sparc-iac#298 (Phase 3 — permission audit), 2026-05-26 audit run
-- (documented in docs/dev/oidc_permission_audit.md).
--
-- Window: April + May 2026 (covers ~30 days back from 2026-05-26). The
-- calendar-month partition predicate is cheaper than a date-range scan.
-- For re-runs in later months, update the month IN (...) clause to cover
-- the trailing-30-day window.

SELECT
    eventSource,
    eventName,
    COUNT(*) AS call_count,
    SUM(CASE WHEN errorCode IS NOT NULL AND errorCode <> '' THEN 1 ELSE 0 END) AS error_count,
    MIN(eventTime) AS first_seen,
    MAX(eventTime) AS last_seen
FROM sparc_audit.cloudtrail_logs
WHERE year = '2026'
  AND month IN ('04', '05')
  AND userIdentity.sessionContext.sessionIssuer.arn = 'arn:aws:iam::123456789012:role/sparc-iac-github-actions'
GROUP BY eventSource, eventName
ORDER BY eventSource ASC, eventName ASC;
