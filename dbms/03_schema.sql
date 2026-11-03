-- Findr DBMS milestone: PostgreSQL 14+
-- Run in a NEW, EMPTY database. This is a proposed coursework schema;
-- confirm the assumptions in 01_normalization.md with your team/faculty.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(120) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    phone VARCHAR(30),
    profile_image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE communities (
    community_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(160) NOT NULL,
    community_type VARCHAR(24) NOT NULL CHECK
        (community_type IN ('COLLEGE', 'HOSTEL', 'RESIDENTIAL_COLONY', 'OTHER')),
    description TEXT,
    address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (name, community_type)
);

CREATE TABLE community_memberships (
    membership_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    community_id UUID NOT NULL REFERENCES communities(community_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    role VARCHAR(24) NOT NULL DEFAULT 'MEMBER'
        CHECK (role IN ('MEMBER', 'COMMUNITY_ADMIN')),
    membership_status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (membership_status IN ('PENDING', 'ACTIVE', 'SUSPENDED')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (community_id, user_id)
);

CREATE TABLE categories (
    category_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_name VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE items (
    item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES users(user_id),
    community_id UUID NOT NULL REFERENCES communities(community_id),
    category_id UUID NOT NULL REFERENCES categories(category_id),
    report_type VARCHAR(10) NOT NULL CHECK (report_type IN ('LOST', 'FOUND')),
    title VARCHAR(160) NOT NULL,
    description TEXT NOT NULL,
    event_date DATE NOT NULL,
    location_label VARCHAR(240) NOT NULL,
    latitude NUMERIC(9,6),
    longitude NUMERIC(9,6),
    status VARCHAR(20) NOT NULL DEFAULT 'OPEN' CHECK
        (status IN ('OPEN', 'CLAIM_PENDING', 'CLAIM_APPROVED', 'RETURNED', 'CLOSED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Both coordinates must be absent, or both present and in range.
    CHECK (
        (latitude IS NULL AND longitude IS NULL)
        OR
        (latitude IS NOT NULL AND longitude IS NOT NULL
         AND latitude BETWEEN -90 AND 90
         AND longitude BETWEEN -180 AND 180)
    )
);

CREATE TABLE item_images (
    image_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID NOT NULL REFERENCES items(item_id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE verification_questions (
    question_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID NOT NULL UNIQUE REFERENCES items(item_id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    -- Store an Argon2id (or similarly appropriate password-hash) result, not plaintext.
    answer_hash TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE claims (
    claim_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID NOT NULL REFERENCES items(item_id),
    claimant_id UUID NOT NULL REFERENCES users(user_id),
    -- Raw verification answers are deliberately NOT stored in this table.
    -- Backend verifies the answer first, then records the successful verification time.
    verification_passed_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'WITHDRAWN')),
    review_note TEXT,
    reviewed_by UUID REFERENCES users(user_id),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (reviewed_by IS NULL OR reviewed_by <> claimant_id),
    CHECK (
        (status IN ('PENDING', 'WITHDRAWN') AND reviewed_by IS NULL AND reviewed_at IS NULL)
        OR
        (status IN ('APPROVED', 'REJECTED') AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
    )
);

-- One active claim per claimant/item; withdrawn/rejected claims may be resubmitted.
CREATE UNIQUE INDEX uq_claim_item_claimant_active
    ON claims(item_id, claimant_id)
    WHERE status IN ('PENDING', 'APPROVED');

-- At most one approved claim can exist for a found report.
CREATE UNIQUE INDEX uq_one_approved_claim_per_item
    ON claims(item_id)
    WHERE status = 'APPROVED';

CREATE TABLE handovers (
    handover_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    claim_id UUID NOT NULL UNIQUE REFERENCES claims(claim_id),
    scheduled_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    handover_location TEXT,
    confirmation_note TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'SCHEDULED'
        CHECK (status IN ('SCHEDULED', 'COMPLETED', 'CANCELLED')),
    CHECK (
        (status = 'COMPLETED' AND completed_at IS NOT NULL)
        OR
        (status <> 'COMPLETED' AND completed_at IS NULL)
    )
);

CREATE TABLE notifications (
    notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    related_item_id UUID REFERENCES items(item_id) ON DELETE SET NULL,
    related_claim_id UUID REFERENCES claims(claim_id) ON DELETE SET NULL,
    notification_type VARCHAR(40) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enforce that verification questions belong only to FOUND reports.
CREATE OR REPLACE FUNCTION findr_check_verification_item()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_report_type VARCHAR(10);
BEGIN
    SELECT report_type INTO v_report_type
    FROM items WHERE item_id = NEW.item_id;
    IF NOT FOUND OR v_report_type <> 'FOUND' THEN
        RAISE EXCEPTION 'A verification question can only belong to an existing FOUND report';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_verification_question_found_only
BEFORE INSERT OR UPDATE OF item_id ON verification_questions
FOR EACH ROW EXECUTE FUNCTION findr_check_verification_item();

-- Prevent changing a report from FOUND to LOST after claims/questions exist.
CREATE OR REPLACE FUNCTION findr_protect_report_type()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.report_type <> OLD.report_type AND EXISTS (
        SELECT 1 FROM verification_questions vq WHERE vq.item_id = OLD.item_id
    ) THEN
        RAISE EXCEPTION 'Report type cannot be changed while a verification question exists';
    END IF;
    IF NEW.report_type <> OLD.report_type AND EXISTS (
        SELECT 1 FROM claims cl WHERE cl.item_id = OLD.item_id
    ) THEN
        RAISE EXCEPTION 'Report type cannot be changed after claims exist';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_protect_item_report_type
BEFORE UPDATE OF report_type ON items
FOR EACH ROW EXECUTE FUNCTION findr_protect_report_type();

-- Enforce that claims target FOUND reports and cannot be submitted by the finder.
CREATE OR REPLACE FUNCTION findr_check_claim()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_report_type VARCHAR(10); v_reporter UUID; v_item_status VARCHAR(20);
BEGIN
    SELECT report_type, reporter_id, status
      INTO v_report_type, v_reporter, v_item_status
    FROM items WHERE item_id = NEW.item_id FOR KEY SHARE;
    IF NOT FOUND OR v_report_type <> 'FOUND' THEN
        RAISE EXCEPTION 'A claim must reference an existing FOUND report';
    END IF;
    IF NEW.claimant_id = v_reporter THEN
        RAISE EXCEPTION 'A user cannot claim their own found report';
    END IF;
    IF TG_OP = 'INSERT' AND v_item_status NOT IN ('OPEN', 'CLAIM_PENDING') THEN
        RAISE EXCEPTION 'This item is not accepting claims';
    END IF;
    IF NEW.status IN ('APPROVED', 'REJECTED') THEN
        IF NEW.reviewed_by IS DISTINCT FROM v_reporter OR NEW.reviewed_at IS NULL THEN
            RAISE EXCEPTION 'Only the finder may approve or reject a claim in this workflow';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_claim_integrity
BEFORE INSERT OR UPDATE OF item_id, claimant_id, status, reviewed_by, reviewed_at ON claims
FOR EACH ROW EXECUTE FUNCTION findr_check_claim();

-- Handover creation is intentionally performed by the atomic W4 workflow
-- in 04_queries.sql. Restrict direct INSERT/UPDATE privileges on handovers
-- to the trusted backend/database role; a cross-table CHECK constraint cannot
-- safely enforce this rule during a multi-CTE state transition.

-- Indexes for common filters, joins and user dashboards.
CREATE INDEX idx_items_community_type_status_date
    ON items(community_id, report_type, status, event_date DESC);
CREATE INDEX idx_items_category ON items(category_id);
CREATE INDEX idx_items_reporter ON items(reporter_id);
CREATE INDEX idx_item_images_item ON item_images(item_id);
CREATE INDEX idx_claims_item_status ON claims(item_id, status);
CREATE INDEX idx_claims_claimant_created ON claims(claimant_id, created_at DESC);
CREATE INDEX idx_notifications_user_read_created
    ON notifications(user_id, is_read, created_at DESC);

INSERT INTO categories(category_name) VALUES
    ('Electronics'), ('Bags'), ('Documents'), ('Clothing'),
    ('Accessories'), ('Keys'), ('Water Bottles'), ('Other')
ON CONFLICT (category_name) DO NOTHING;
