CREATE TABLE IF NOT EXISTS public.pending_admins
(
    pending_admin_id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES public."Users"(user_id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    approver_comment TEXT
);

CREATE INDEX IF NOT EXISTS pending_admins_user_id_idx ON public.pending_admins(user_id);
