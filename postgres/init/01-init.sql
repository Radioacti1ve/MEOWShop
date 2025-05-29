CREATE TABLE "Users"(
    "user_id" SERIAL,
    "username" VARCHAR(255) NOT NULL,
    "email" VARCHAR(255) NOT NULL UNIQUE,
    "password" VARCHAR(255) NOT NULL,
    "role" VARCHAR(255) DEFAULT 'user',
    "registration_date" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE "Users" ADD PRIMARY KEY("user_id");
