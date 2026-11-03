# Findr relational database normalization (1NF, 2NF, 3NF; BCNF discussion)

## 1. Scope and assumptions

This is a proposed relational model for the Findr lost-and-found platform. It is not evidence that the application has already been implemented. Confirm these rules with the team and course instructor before treating the design as final:

1. A community represents a college, hostel, residential colony, or another defined group.
2. A user may join more than one community; membership is therefore a separate relation.
3. Each item report is either `LOST` or `FOUND`.
4. A `FOUND` report may have one private verification question; a `LOST` report does not.
5. Claims are submitted against `FOUND` reports only. The finder reviews a claim.
6. Multiple claimants may submit claims for one found report, but at most one claim may be approved.
7. One handover record is associated with an approved claim.
8. A report may have multiple images.
9. PostgreSQL is the DBMS used for this SQL milestone. Confirm that this matches the faculty requirement; do not assume it must also be the eventual production database.

## 2. Unnormalized form (UNF)

A spreadsheet-style starting relation could be:

`FINDR_RECORD(UserName, UserEmail, CommunityName, ItemTitle, CategoryName, ReportType, PhotoURLs, ClaimantNames, ClaimAnswers, VerificationQuestion, VerificationAnswer, NotificationMessages)`

This is unnormalized because attributes such as `PhotoURLs`, `ClaimantNames`, `ClaimAnswers`, and `NotificationMessages` can contain repeating groups or multiple values. It also mixes facts about users, communities, reports, claims, and notifications, creating update, insertion, and deletion anomalies.

## 3. First Normal Form (1NF)

1NF requires each attribute value to be atomic and each row to be uniquely identifiable. Repeating groups are separated into their own relations:

- `users(user_id, full_name, email, password_hash, ...)`
- `communities(community_id, name, community_type, ...)`
- `community_memberships(membership_id, community_id, user_id, ...)`
- `categories(category_id, category_name)`
- `items(item_id, reporter_id, community_id, category_id, report_type, title, ...)`
- `item_images(image_id, item_id, image_url, ...)`
- `verification_questions(question_id, item_id, question_text, answer_hash, ...)`
- `claims(claim_id, item_id, claimant_id, verification_passed_at, ...)`
- `handovers(handover_id, claim_id, ...)`
- `notifications(notification_id, user_id, ...)`

Each image, membership, claim, and notification is stored as a separate row. No column stores a list of values.

## 4. Second Normal Form (2NF)

2NF requires 1NF and that every non-prime attribute depend on the whole of every candidate key (no partial dependency on part of a composite candidate key).

In a flattened item-image relation with candidate key `(item_id, image_id)`, item title and description depend on `item_id`, not on the whole composite key. Separating `items` from `item_images` removes this partial dependency. Similarly, user attributes depend on `user_id`, community attributes on `community_id`, and category attributes on `category_id`; they are stored in separate relations. The many-to-many user/community relationship is represented by `community_memberships`, whose alternate candidate key is `(community_id, user_id)`.

## 5. Third Normal Form (3NF)

3NF requires 2NF and, for every non-trivial functional dependency `X → A`, either `X` is a superkey or `A` is a prime attribute. The principal functional dependencies used in this design are:

| Relation | Candidate key(s) / important functional dependencies |
|---|---|
| `users` | `user_id → full_name, email, password_hash, phone, profile_image_url, created_at`; `email` is also unique and therefore a candidate key. |
| `communities` | `community_id → name, community_type, description, address, created_at`. `(name, community_type)` is declared unique. |
| `community_memberships` | `membership_id → community_id, user_id, role, membership_status, joined_at`; `(community_id, user_id)` is also unique. |
| `categories` | `category_id → category_name`; `category_name` is unique. |
| `items` | `item_id → reporter_id, community_id, category_id, report_type, title, description, event_date, location_label, latitude, longitude, status, created_at, updated_at`. |
| `item_images` | `image_id → item_id, image_url, uploaded_at`. |
| `verification_questions` | `question_id → item_id, question_text, answer_hash, is_active, created_at`; `item_id` is unique in the one-question-per-report assumption. |
| `claims` | `claim_id → item_id, claimant_id, verification_passed_at, status, review_note, reviewed_by, reviewed_at, created_at, updated_at`. |
| `handovers` | `handover_id → claim_id, scheduled_at, completed_at, handover_location, confirmation_note, status`; `claim_id` is unique. |
| `notifications` | `notification_id → user_id, related_item_id, related_claim_id, notification_type, message, is_read, created_at`. |

Descriptive facts are stored with their own entity: category names are not repeated in `items`, reporter names/emails are not copied into `items`, and item titles are not copied into `claims`. JOINs retrieve those attributes when required. This avoids the main transitive-dependency and update-anomaly problems in the original flat relation.

## 6. BCNF (optional discussion)

BCNF requires every determinant in every non-trivial functional dependency to be a superkey. Based on the functional dependencies listed above, the determinants in the core relations are declared candidate keys or superkeys. The design is therefore intended to satisfy BCNF under the stated assumptions. This conclusion depends on the completeness of the functional dependencies: if the team identifies additional business rules (for example, a different uniqueness rule for communities), the candidate keys and BCNF analysis must be revisited.

## 7. Integrity rules represented in the schema/workflows

- Primary keys identify rows; foreign keys maintain references.
- Email, category name, membership pair, verification-question item, and handover claim are unique as specified.
- An item has one report type (`LOST` or `FOUND`).
- Latitude and longitude must both be NULL or both be present and within valid ranges.
- A trigger prevents verification questions from being attached to LOST reports.
- A trigger prevents claims against LOST reports and self-claims.
- A partial unique index allows at most one approved claim per item. W4 rejects the other pending claims when one claim is approved.
- A trigger restricts claim approval/rejection to the finder in this proposed workflow.
- The W4 database workflow creates a handover after a claim is approved; direct writes to the handovers table must be restricted to the trusted backend/database role.
- The expected verification answer is stored as a password hash. The raw claimant answer is verified by backend code and is not stored in the claims table.

## 8. Decisions still requiring confirmation

- Does one user belong to one community or multiple communities?
- Is PostgreSQL explicitly required/accepted for this DBMS milestone?
- Can a found report have exactly one verification question, or should it support multiple questions?
- Can administrators approve/reject claims, or only the finder?
- What is the exact policy for multiple pending claims and claim withdrawal?
- Are community memberships approved by an administrator?
- Which contact details, if any, are shared after claim approval?

Do not claim these assumptions are implemented in the running app until the corresponding application/backend behaviour exists.
