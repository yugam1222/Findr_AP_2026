# Findr Database Normalization Report
## UNF, 1NF, 2NF, 3NF and BCNF Analysis

**Project:** Findr — Community Lost-and-Found Platform  
**DBMS:** PostgreSQL 14+  
**Document:** Relational Database Design and Normalization  
**Status:** Proposed logical design aligned with `03_schema.sql`

---

## 1. Purpose and Scope

This report explains how the Findr relational database is structured to reduce data redundancy and prevent insertion, update and deletion anomalies.

The analysis is based on the proposed PostgreSQL schema documented in `03_schema.sql`. It explains the transformation from an unnormalized representation to a structured relational model and evaluates the resulting relations against 1NF, 2NF, 3NF and BCNF.

Normalization decisions are distinguished from business rules enforced through SQL constraints, indexes, triggers and application workflows.

### 1.1 Business Assumptions

The following assumptions form the basis of this normalization analysis:

1. A community represents a college, hostel, residential colony or another defined group.
2. A user may belong to multiple communities. Therefore, membership is maintained as a separate relation.
3. Each item report is classified as either `LOST` or `FOUND`.
4. A `FOUND` report may have at most one private verification question. A `LOST` report cannot have a verification question.
5. Claims can only be submitted against `FOUND` reports.
6. A user cannot submit a claim against their own found report.
7. Multiple users may submit claims for one found report, but at most one claim can be approved.
8. A rejected or withdrawn claim may be submitted again.
9. Each claim can have at most one associated handover record.
10. An item report may contain multiple images.
11. PostgreSQL 14+ is the target DBMS for this coursework milestone.

These assumptions must be confirmed with the project team and instructor. Any change in business rules may require modifications to the schema and normalization analysis.

### 1.2 Relations in the Proposed Database

The proposed database contains ten principal relations:

| Relation | Purpose |
|---|---|
| `users` | Stores user account and profile information. |
| `communities` | Stores information about colleges, hostels and other communities. |
| `community_memberships` | Represents the many-to-many relationship between users and communities. |
| `categories` | Maintains the available item categories. |
| `items` | Stores LOST and FOUND item reports. |
| `item_images` | Stores images associated with item reports. |
| `verification_questions` | Stores private verification questions and answer hashes. |
| `claims` | Stores claims submitted by users and their review status. |
| `handovers` | Stores information about item handovers. |
| `notifications` | Stores notifications associated with users. |

---

## 2. Unnormalized Form (UNF)

An initial spreadsheet-style representation of the Findr platform could be:

```text
FINDR_RECORD(
    UserName,
    UserEmail,
    CommunityName,
    CommunityType,
    ItemTitle,
    CategoryName,
    ReportType,
    Description,
    PhotoURLs,
    ClaimantNames,
    ClaimStatuses,
    VerificationQuestion,
    VerificationAnswer,
    NotificationMessages
)
```

This representation is unnormalized because multiple values may be stored within individual attributes.

For example:

- `PhotoURLs` may contain multiple image URLs.
- `ClaimantNames` may contain multiple claimants for the same found report.
- `ClaimStatuses` may contain multiple claim statuses.
- `NotificationMessages` may contain multiple notifications.
- User, community, item and claim information is mixed within the same record.

### 2.1 Problems with the UNF Design

**1. Update anomaly**

If a user's email address changes, the same information may need to be updated in multiple records. Missing one occurrence could result in inconsistent data.

**2. Insertion anomaly**

A new community or category cannot be stored independently without introducing an associated user or item record.

**3. Deletion anomaly**

Deleting the only item associated with a community could unintentionally remove the only stored occurrence of that community's information.

**4. Repeating groups**

Multiple images, claims and notifications cannot be maintained efficiently when stored as lists inside individual attributes.

The UNF representation therefore creates redundancy and makes data maintenance difficult.

---

## 3. First Normal Form (1NF)

A relation satisfies First Normal Form when:

- Every attribute contains a single atomic value.
- Repeating groups are eliminated.
- Each record can be uniquely identified using a key.

To achieve 1NF, the combined UNF representation is separated into individual relations.

```text
USERS(
    user_id,
    full_name,
    email,
    password_hash,
    phone,
    profile_image_url,
    created_at
)

COMMUNITIES(
    community_id,
    name,
    community_type,
    description,
    address,
    created_at
)

COMMUNITY_MEMBERSHIPS(
    membership_id,
    community_id,
    user_id,
    role,
    membership_status,
    joined_at
)

CATEGORIES(
    category_id,
    category_name
)

ITEMS(
    item_id,
    reporter_id,
    community_id,
    category_id,
    report_type,
    title,
    description,
    event_date,
    location_label,
    latitude,
    longitude,
    status,
    created_at,
    updated_at
)

ITEM_IMAGES(
    image_id,
    item_id,
    image_url,
    uploaded_at
)

VERIFICATION_QUESTIONS(
    question_id,
    item_id,
    question_text,
    answer_hash,
    is_active,
    created_at
)

CLAIMS(
    claim_id,
    item_id,
    claimant_id,
    verification_passed_at,
    status,
    review_note,
    reviewed_by,
    reviewed_at,
    created_at,
    updated_at
)

HANDOVERS(
    handover_id,
    claim_id,
    scheduled_at,
    completed_at,
    handover_location,
    confirmation_note,
    status
)

NOTIFICATIONS(
    notification_id,
    user_id,
    related_item_id,
    related_claim_id,
    notification_type,
    message,
    is_read,
    created_at
)
```

### 3.1 1NF Decomposition

The following transformations remove repeating groups:

1. Multiple image URLs are stored as individual records in `item_images`.
2. Multiple claims are stored as separate records in `claims`.
3. User-community relationships are maintained through individual records in `community_memberships`.
4. Notifications are stored as separate records in `notifications`.
5. Verification information is separated into `verification_questions`, preventing private verification data from being mixed with general item information.

Primary keys uniquely identify the records in each relation.

**Result:** The proposed relations contain atomic attribute values and do not store repeating lists of images, claims, memberships or notifications.

---

## 4. Second Normal Form (2NF)

A relation satisfies Second Normal Form when:

1. It is already in 1NF.
2. Every non-prime attribute is fully functionally dependent on every candidate key.

In other words, there must be no partial dependency in which a non-key attribute depends on only a proper subset of a composite candidate key.

### 4.1 Example: Item and Image Relationship

Consider a hypothetical flattened relation:

```text
ITEM_IMAGE_FLAT(
    item_id,
    image_id,
    item_title,
    item_description,
    image_url,
    uploaded_at
)
```

Assume the candidate key is:

```text
(item_id, image_id)
```

The functional dependencies are:

```text
(item_id, image_id) -> image_url, uploaded_at

item_id -> item_title, item_description
```

Here, `item_title` and `item_description` depend only on `item_id`, which is a proper subset of the composite candidate key.

This is a partial dependency and violates 2NF.

### 4.2 Decomposition

The relation is decomposed into:

```text
ITEMS(
    item_id,
    item_title,
    item_description,
    ...
)

ITEM_IMAGES(
    image_id,
    item_id,
    image_url,
    uploaded_at
)
```

Now:

- Item attributes are stored in `items`.
- Image attributes are stored in `item_images`.
- `item_id` acts as a foreign key connecting images to their respective item reports.

The composite-key example illustrates the partial dependency that would arise in a flattened representation. The actual SQL schema uses `image_id` as the primary key of `item_images`.

### 4.3 User and Community Membership

The relationship between users and communities is many-to-many.

A user may join multiple communities, while a community may contain multiple users.

Therefore, the relationship is represented using:

```text
COMMUNITY_MEMBERSHIPS(
    membership_id,
    community_id,
    user_id,
    role,
    membership_status,
    joined_at
)
```

The schema defines:

- `membership_id` as the primary key.
- `(community_id, user_id)` as an alternate candidate key through a UNIQUE constraint.

Membership-specific attributes depend on the complete membership association.

User profile information remains in `users`, while community information remains in `communities`.

### 4.4 Other Decomposition Decisions

- User attributes are maintained in `users`.
- Community attributes are maintained in `communities`.
- Category names are maintained in `categories`.
- Item information is maintained in `items`.
- Claim-specific information is maintained in `claims`.

This prevents attributes from being unnecessarily repeated across related records.

**Result:** The decomposition eliminates the identified partial dependency and ensures that attributes are stored with the entity or relationship they describe.

---

## 5. Third Normal Form (3NF)

A relation satisfies Third Normal Form when:

1. It is already in 2NF.
2. For every non-trivial functional dependency `X -> A`, either:
   - `X` is a superkey, or
   - `A` is a prime attribute.

A prime attribute is an attribute that belongs to at least one candidate key.

### 5.1 Candidate Keys and Functional Dependencies

The following table identifies the candidate keys supported by the declared primary key and UNIQUE constraints in the proposed schema.

| Relation | Candidate Keys | Principal Functional Dependencies |
|---|---|---|
| `users` | `user_id`, `email` | `user_id -> full_name, email, password_hash, phone, profile_image_url, created_at` |
| `communities` | `community_id`, `(name, community_type)` | `community_id -> name, community_type, description, address, created_at` |
| `community_memberships` | `membership_id`, `(community_id, user_id)` | `membership_id -> community_id, user_id, role, membership_status, joined_at` |
| `categories` | `category_id`, `category_name` | `category_id -> category_name` |
| `items` | `item_id` | `item_id -> reporter_id, community_id, category_id, report_type, title, description, event_date, location_label, latitude, longitude, status, created_at, updated_at` |
| `item_images` | `image_id` | `image_id -> item_id, image_url, uploaded_at` |
| `verification_questions` | `question_id`, `item_id` | `question_id -> item_id, question_text, answer_hash, is_active, created_at` |
| `claims` | `claim_id` | `claim_id -> item_id, claimant_id, verification_passed_at, status, review_note, reviewed_by, reviewed_at, created_at, updated_at` |
| `handovers` | `handover_id`, `claim_id` | `handover_id -> claim_id, scheduled_at, completed_at, handover_location, confirmation_note, status` |
| `notifications` | `notification_id` | `notification_id -> user_id, related_item_id, related_claim_id, notification_type, message, is_read, created_at` |

### 5.2 Explanation of Important Functional Dependencies

**Users**

```text
user_id -> full_name, email, password_hash, phone,
           profile_image_url, created_at
```

Each user identifier determines the corresponding user information.

The email address is also unique and non-null, making it an alternate candidate key.

**Communities**

```text
community_id -> name, community_type, description,
                address, created_at
```

The combination `(name, community_type)` is also declared unique in the SQL schema.

**Community Memberships**

```text
membership_id -> community_id, user_id, role,
                 membership_status, joined_at
```

The combination `(community_id, user_id)` is unique, preventing duplicate membership records for the same user and community.

**Categories**

```text
category_id -> category_name
```

The category name is unique, ensuring that each category is represented by one record.

**Items**

```text
item_id -> reporter_id, community_id, category_id,
           report_type, title, description, event_date,
           location_label, latitude, longitude,
           status, created_at, updated_at
```

Each item identifier determines its report details.

**Item Images**

```text
image_id -> item_id, image_url, uploaded_at
```

Each image is uniquely identified, while `item_id` references the associated report.

**Verification Questions**

```text
question_id -> item_id, question_text, answer_hash,
               is_active, created_at
```

The `item_id` column is unique, supporting the assumption that each report has at most one verification question.

**Claims**

```text
claim_id -> item_id, claimant_id, verification_passed_at,
            status, review_note, reviewed_by,
            reviewed_at, created_at, updated_at
```

Each claim is identified independently using `claim_id`.

The pair `(item_id, claimant_id)` is not a permanent candidate key because rejected or withdrawn claims may be resubmitted. The partial unique index only prevents duplicate active claims.

**Handovers**

```text
handover_id -> claim_id, scheduled_at, completed_at,
               handover_location, confirmation_note, status
```

The `claim_id` column is unique, so each claim can have at most one handover record.

**Notifications**

```text
notification_id -> user_id, related_item_id,
                   related_claim_id, notification_type,
                   message, is_read, created_at
```

Each notification is uniquely identified using its notification identifier.

### 5.3 Prevention of Transitive Dependencies

The design avoids storing descriptive information redundantly in unrelated relations.

Examples:

1. Category names are stored in `categories`, while `items` stores only `category_id`.
2. Reporter names and email addresses are stored in `users`, while `items` stores `reporter_id`.
3. Community details are stored in `communities`, while `items` stores `community_id`.
4. Item titles and descriptions are stored in `items`, while `claims` stores `item_id`.
5. Claimant and reviewer details are retrieved through user references rather than duplicated in `claims`.

This reduces redundancy and prevents update anomalies.

### 5.4 3NF Conclusion

Based on the functional dependencies and candidate keys declared in the current schema, the proposed relations are designed to satisfy Third Normal Form.

Each listed non-trivial functional dependency has a candidate key or superkey as its determinant.

This conclusion is based on the documented attributes and business assumptions. Any additional business rule introducing new functional dependencies must be evaluated before the design is finalized.

---

## 6. Boyce-Codd Normal Form (BCNF)

Boyce-Codd Normal Form is a stronger form of 3NF.

A relation satisfies BCNF if, for every non-trivial functional dependency:

```text
X -> Y
```

`X` must be a superkey.

### 6.1 BCNF Evaluation

Based on the functional dependencies documented in Section 5:

- In `users`, both `user_id` and `email` are candidate keys.
- In `communities`, `community_id` and `(name, community_type)` are candidate keys.
- In `community_memberships`, `membership_id` and `(community_id, user_id)` are candidate keys.
- In `categories`, both `category_id` and `category_name` are candidate keys.
- In `verification_questions`, `question_id` and `item_id` are candidate keys.
- In `handovers`, `handover_id` and `claim_id` are candidate keys.
- In `items`, `item_images`, `claims` and `notifications`, the declared primary keys determine their respective non-key attributes.

Therefore, the functional dependencies currently identified are consistent with BCNF because their determinants are candidate keys or superkeys.

### 6.2 BCNF Limitation

This conclusion depends on the completeness of the functional dependencies.

For example, if a future business rule states that a community name must be globally unique regardless of community type, the candidate-key analysis of `communities` must be revisited.

Similarly, any additional uniqueness rules or relationships introduced during implementation must be included in the BCNF evaluation.

**Conclusion:** The current design is intended to satisfy BCNF under the stated functional dependencies and business assumptions.

---

## 7. Integrity Constraints and Business Rules

Normalization organizes the data into relations. Additional integrity rules are implemented separately through database constraints, indexes, triggers and application workflows.

| Integrity Rule | Implementation Mechanism |
|---|---|
| Every record has a unique identifier | Primary keys |
| Referenced records must exist | Foreign keys |
| User email must be unique | UNIQUE constraint |
| Community name/type combination must be unique | UNIQUE constraint |
| A user can have one membership per community | UNIQUE constraint |
| Category names must be unique | UNIQUE constraint |
| Item report type must be LOST or FOUND | CHECK constraint |
| Latitude and longitude must both be absent or valid | CHECK constraint |
| A report can have at most one verification question | UNIQUE constraint |
| Verification questions can only belong to FOUND reports | Trigger |
| Claims can only target FOUND reports | Trigger |
| Users cannot claim their own found reports | Trigger |
| A claimant cannot have duplicate active claims for an item | Partial unique index |
| Only one claim per item can be approved | Partial unique index |
| Only the finder can approve or reject claims in this workflow | Trigger |
| Each claim can have at most one handover | UNIQUE constraint |
| A completed handover must have a completion timestamp | CHECK constraint |
| Approval and rejection of competing claims occur together | W4 workflow |
| Handover completion and item return occur together | W5 workflow |
| Raw verification answers are not stored in claims | Backend verification process |

The schema uses the following important database objects:

- `trg_verification_question_found_only`
- `trg_protect_item_report_type`
- `trg_claim_integrity`
- `uq_claim_item_claimant_active`
- `uq_one_approved_claim_per_item`

Direct writes to the `handovers` table are intended to be restricted to the trusted backend/database role. Such role permissions must be configured separately; they are not established merely by defining the table.

---

## 8. Design Limitations and Decisions Requiring Confirmation

The following decisions require confirmation from the project team and instructor:

1. Is membership in multiple communities permitted in the final application?
2. Is PostgreSQL 14+ accepted for the DBMS milestone?
3. Should a found report support one verification question or multiple questions?
4. Can administrators review claims, or is claim approval restricted to the finder?
5. What are the permitted transitions for pending, rejected and withdrawn claims?
6. Who is authorized to approve community memberships?
7. Which contact details may be shared after claim approval?
8. Should images have additional ordering or uniqueness rules?
9. How should simultaneous claim submissions be handled?

These are business-policy decisions rather than normalization errors. Any agreed changes must be reflected in the database schema and corresponding documentation.

---

## 9. Conclusion

The proposed Findr relational database separates user, community, membership, category, item, image, verification-question, claim, handover and notification information into distinct relations.

The decomposition eliminates repeating groups, addresses the partial dependency demonstrated by the flattened item-image example, and ensures that descriptive attributes are maintained with the entities or relationships they describe.

Based on the functional dependencies and candidate keys declared in the proposed PostgreSQL schema, the design is intended to satisfy 1NF, 2NF and 3NF. The listed dependencies are also consistent with BCNF under the stated assumptions.

The design reduces data redundancy and helps prevent insertion, update and deletion anomalies while maintaining referential integrity through primary keys, foreign keys, uniqueness constraints, checks, indexes and triggers.

**Evidence limitation:** This document describes the proposed relational design. It does not claim that the complete application backend has been implemented, that every SQL query and trigger has been tested, or that all performance benchmarks have been completed. Those claims require separate implementation and testing evidence.