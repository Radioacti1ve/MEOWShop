CREATE TABLE IF NOT EXISTS "PendingSellers" (
    "pending_seller_id" SERIAL PRIMARY KEY,
    "user_id" INTEGER REFERENCES "Users"("user_id") ON DELETE CASCADE,
    "status" VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    "created_at" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    "admin_comment" TEXT,
    UNIQUE("user_id")
);

CREATE INDEX IF NOT EXISTS "idx_pending_sellers_status" ON "PendingSellers"(status);

CREATE OR REPLACE FUNCTION update_pending_sellers_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_pending_sellers_timestamp
    BEFORE UPDATE ON "PendingSellers"
    FOR EACH ROW
    EXECUTE FUNCTION update_pending_sellers_updated_at();