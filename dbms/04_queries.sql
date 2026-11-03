-- Findr SQL query catalogue | PostgreSQL | run with psql
-- Define psql variables before running, for example:
-- \set community_id '00000000-0000-0000-0000-000000000001'
-- \set user_id '00000000-0000-0000-0000-000000000002'
-- Text values are quoted by psql using :'variable'.
-- IMPORTANT: For W3, the backend must verify the submitted answer against
-- verification_questions.answer_hash BEFORE executing the INSERT. Never expose answer_hash.

-- =============================== READ QUERIES ===============================

-- READ R1: Browse open FOUND reports in a community (JOIN + image aggregation)
SELECT i.item_id, i.title, i.description, cat.category_name,
       u.full_name AS reporter_name, i.event_date, i.location_label,
       COALESCE(img.images, ARRAY[]::TEXT[]) AS image_urls
FROM items i
JOIN categories cat ON cat.category_id = i.category_id
JOIN users u ON u.user_id = i.reporter_id
LEFT JOIN LATERAL (
    SELECT array_agg(ii.image_url ORDER BY ii.uploaded_at) AS images
    FROM item_images ii WHERE ii.item_id = i.item_id
) img ON TRUE
WHERE i.community_id = :'community_id'
  AND i.report_type = 'FOUND'
  AND i.status IN ('OPEN', 'CLAIM_PENDING')
ORDER BY i.created_at DESC
LIMIT 20;

-- READ R2: Search reports by keyword in a community (JOINs)
SELECT i.item_id, i.title, i.report_type, i.event_date,
       i.location_label, cat.category_name, com.name AS community_name
FROM items i
JOIN categories cat ON cat.category_id = i.category_id
JOIN communities com ON com.community_id = i.community_id
WHERE i.community_id = :'community_id'
  AND i.status IN ('OPEN', 'CLAIM_PENDING')
  AND (i.title ILIKE '%' || :'keyword' || '%'
       OR i.description ILIKE '%' || :'keyword' || '%')
ORDER BY i.created_at DESC;

-- READ R3: Item detail (reporter and category JOINs; deliberately excludes private answer hash)
SELECT i.item_id, i.title, i.description, i.report_type, i.status,
       i.event_date, i.location_label, i.latitude, i.longitude,
       cat.category_name, u.full_name AS reporter_name
FROM items i
JOIN categories cat ON cat.category_id = i.category_id
JOIN users u ON u.user_id = i.reporter_id
WHERE i.item_id = :'item_id';

-- READ R4: Current user's LOST reports
SELECT i.item_id, i.title, i.status, i.event_date, i.location_label,
       com.name AS community_name, cat.category_name
FROM items i
JOIN communities com ON com.community_id = i.community_id
JOIN categories cat ON cat.category_id = i.category_id
WHERE i.reporter_id = :'user_id' AND i.report_type = 'LOST'
ORDER BY i.created_at DESC;

-- READ R5: Pending claims received by the finder
SELECT cl.claim_id, cl.status, cl.created_at,
       claimant.full_name AS claimant_name, i.title AS item_title, i.item_id
FROM claims cl
JOIN items i ON i.item_id = cl.item_id
JOIN users claimant ON claimant.user_id = cl.claimant_id
WHERE i.reporter_id = :'finder_id' AND cl.status = 'PENDING'
ORDER BY cl.created_at ASC;

-- READ R6: Current user's claim history
SELECT cl.claim_id, cl.status, cl.created_at,
       i.title AS item_title, i.location_label,
       finder.full_name AS finder_name
FROM claims cl
JOIN items i ON i.item_id = cl.item_id
JOIN users finder ON finder.user_id = i.reporter_id
WHERE cl.claimant_id = :'user_id'
ORDER BY cl.created_at DESC;

-- READ R7: Current user's notifications
SELECT notification_id, notification_type, message, is_read, created_at
FROM notifications
WHERE user_id = :'user_id'
ORDER BY created_at DESC
LIMIT 30;

-- =============================== WRITE QUERIES ==============================

-- WRITE W1: Create a LOST or FOUND report
INSERT INTO items (
    reporter_id, community_id, category_id, report_type,
    title, description, event_date, location_label, latitude, longitude
) VALUES (
    :'reporter_id', :'community_id', :'category_id', :'report_type',
    :'title', :'description', :'event_date', :'location_label',
    NULLIF(:'latitude', '')::NUMERIC, NULLIF(:'longitude', '')::NUMERIC
)
RETURNING item_id;

-- WRITE W2: Add an image only when the authenticated uploader owns the report
INSERT INTO item_images(item_id, image_url)
SELECT i.item_id, :'image_url'
FROM items i
WHERE i.item_id = :'item_id' AND i.reporter_id = :'reporter_id'
RETURNING image_id;

-- WRITE W3: Submit a claim AFTER backend verification succeeds.
-- The raw answer is not stored. Backend supplies the authenticated claimant_id.
-- Row locking serializes claims against approval/return workflows.
WITH target_item AS MATERIALIZED (
    SELECT item_id
    FROM items
    WHERE item_id = :'item_id'
      AND report_type = 'FOUND'
      AND status IN ('OPEN', 'CLAIM_PENDING')
      AND reporter_id <> :'claimant_id'
    FOR UPDATE
), new_claim AS (
    INSERT INTO claims(item_id, claimant_id, verification_passed_at)
    SELECT item_id, :'claimant_id', NOW() FROM target_item
    RETURNING claim_id, item_id
), mark_pending AS (
    UPDATE items i
    SET status = 'CLAIM_PENDING', updated_at = NOW()
    FROM new_claim nc
    WHERE i.item_id = nc.item_id
    RETURNING i.item_id
)
SELECT nc.claim_id, nc.item_id
FROM new_claim nc JOIN mark_pending mp ON mp.item_id = nc.item_id;

-- WRITE W4: Finder approves one pending claim and creates its handover atomically.
-- If validation fails or another claim has already been approved, this returns zero rows.
WITH locked_target AS MATERIALIZED (
    SELECT cl.claim_id, cl.item_id, cl.claimant_id
    FROM claims cl
    JOIN items i ON i.item_id = cl.item_id
    WHERE cl.claim_id = :'claim_id'
      AND cl.status = 'PENDING'
      AND i.reporter_id = :'finder_id'
      AND i.report_type = 'FOUND'
      AND i.status = 'CLAIM_PENDING'
    FOR UPDATE OF cl, i
), approved_claim AS (
    UPDATE claims cl
    SET status = 'APPROVED', reviewed_by = :'finder_id',
        reviewed_at = NOW(), updated_at = NOW()
    FROM locked_target lt
    WHERE cl.claim_id = lt.claim_id
    RETURNING cl.claim_id, cl.item_id, cl.claimant_id
), updated_item AS (
    UPDATE items i
    SET status = 'CLAIM_APPROVED', updated_at = NOW()
    FROM approved_claim ac
    WHERE i.item_id = ac.item_id
    RETURNING i.item_id
), rejected_other_pending AS (
    UPDATE claims other
    SET status = 'REJECTED', reviewed_by = :'finder_id',
        reviewed_at = NOW(), updated_at = NOW()
    FROM approved_claim ac
    WHERE other.item_id = ac.item_id
      AND other.claim_id <> ac.claim_id
      AND other.status = 'PENDING'
    RETURNING other.claim_id
), created_handover AS (
    INSERT INTO handovers(claim_id)
    SELECT ac.claim_id
    FROM approved_claim ac
    JOIN updated_item ui ON ui.item_id = ac.item_id
    RETURNING handover_id, claim_id
)
SELECT ac.claim_id, ac.item_id, ac.claimant_id, ch.handover_id
FROM approved_claim ac
JOIN updated_item ui ON ui.item_id = ac.item_id
JOIN created_handover ch ON ch.claim_id = ac.claim_id;


-- WRITE W5: Complete a scheduled handover and mark the item RETURNED atomically.
-- Locks all relevant rows and proceeds only when the claim, handover and item
-- are in the correct states.

WITH locked_target AS MATERIALIZED (
    SELECT h.handover_id, cl.item_id
    FROM handovers h
    JOIN claims cl ON cl.claim_id = h.claim_id
    JOIN items i ON i.item_id = cl.item_id
    WHERE cl.claim_id = :'claim_id'
      AND cl.status = 'APPROVED'
      AND h.status = 'SCHEDULED'
      AND i.status = 'CLAIM_APPROVED'
    FOR UPDATE OF h, cl, i
),
completed_handover AS (
    UPDATE handovers h
    SET status = 'COMPLETED',
        completed_at = NOW()
    FROM locked_target lt
    WHERE h.handover_id = lt.handover_id
    RETURNING lt.item_id
),
updated_item AS (
    UPDATE items i
    SET status = 'RETURNED',
        updated_at = NOW()
    FROM completed_handover ch
    WHERE i.item_id = ch.item_id
    RETURNING i.item_id, i.status
)
SELECT * FROM updated_item;


-- WRITE W6: Mark one of the authenticated user's notifications as read
UPDATE notifications
SET is_read = TRUE
WHERE notification_id = :'notification_id'
  AND user_id = :'user_id'
RETURNING notification_id, is_read;

-- WRITE W7: Finder rejects a pending claim; reopen item only if no other active claim remains.
WITH locked_target AS MATERIALIZED (
    SELECT cl.claim_id, cl.item_id
    FROM claims cl
    JOIN items i ON i.item_id = cl.item_id
    WHERE cl.claim_id = :'claim_id'
      AND cl.status = 'PENDING'
      AND i.reporter_id = :'finder_id'
      AND i.status = 'CLAIM_PENDING'
    FOR UPDATE OF cl, i
), rejected_claim AS (
    UPDATE claims cl
    SET status = 'REJECTED', reviewed_by = :'finder_id',
        reviewed_at = NOW(), updated_at = NOW()
    FROM locked_target lt
    WHERE cl.claim_id = lt.claim_id
    RETURNING cl.claim_id, cl.item_id
), recalculated_item AS (
    UPDATE items i
    SET status = CASE
        WHEN EXISTS (
            SELECT 1 FROM claims other
            WHERE other.item_id = i.item_id
              AND other.claim_id <> rc.claim_id
              AND other.status IN ('PENDING', 'APPROVED')
        ) THEN 'CLAIM_PENDING'
        ELSE 'OPEN'
    END,
    updated_at = NOW()
    FROM rejected_claim rc
    WHERE i.item_id = rc.item_id
    RETURNING i.item_id, i.status
)
SELECT rc.claim_id, ri.item_id, ri.status AS item_status
FROM rejected_claim rc
JOIN recalculated_item ri ON ri.item_id = rc.item_id;
