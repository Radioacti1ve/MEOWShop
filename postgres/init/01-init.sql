CREATE TABLE IF NOT EXISTS "Users"(
    "user_id" SERIAL,
    "username" VARCHAR(255) NOT NULL,
    "email" VARCHAR(255) NOT NULL UNIQUE,
    "password" VARCHAR(255) NOT NULL,
    "role" VARCHAR(255) DEFAULT 'user',
    "registration_date" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    "is_active" BOOLEAN NOT NULL DEFAULT TRUE
);
ALTER TABLE "Users" ADD PRIMARY KEY("user_id");

CREATE TABLE IF NOT EXISTS "Products"(
    "product_id" SERIAL NOT NULL,
    "seller_id" INTEGER NOT NULL,
    "product_name" VARCHAR(255) NOT NULL,
    "description" TEXT,
    "category" VARCHAR(255) NOT NULL,
    "price" NUMERIC(12,2) NOT NULL ,
    "in_stock" INTEGER NOT NULL CHECK ("in_stock" >= 0),
    "status" VARCHAR(50) NOT NULL DEFAULT 'available'
);
ALTER TABLE "Products" ADD PRIMARY KEY("product_id");

CREATE TABLE IF NOT EXISTS "Sellers"(
    "seller_id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "description" TEXT
);
ALTER TABLE "Sellers" ADD PRIMARY KEY("seller_id");

CREATE TABLE IF NOT EXISTS "Comments"(
    "comment_id" SERIAL,
    "user_id" INTEGER,
    "reply_to_comment_id" INTEGER,
    "product_id" INTEGER NOT NULL,
    "text" TEXT,
    "rating" INTEGER,
    "created_at" TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL
);
ALTER TABLE "Comments" ADD PRIMARY KEY("comment_id");

CREATE TABLE IF NOT EXISTS "Baskets"(
    "basket_id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL
);
ALTER TABLE "Baskets" ADD PRIMARY KEY("basket_id");
ALTER TABLE "Baskets" ADD CONSTRAINT "baskets_user_id_unique" UNIQUE("user_id");

CREATE TABLE IF NOT EXISTS "Baskets_items"(
    "id" SERIAL NOT NULL,
    "Basket_id" INTEGER NOT NULL,
    "product_id" INTEGER NOT NULL,
    "quantity" INTEGER NOT NULL CHECK ("quantity" > 0),
    "price_" NUMERIC(12,2) NOT NULL
);
ALTER TABLE "Baskets_items" ADD PRIMARY KEY("id");

CREATE TABLE IF NOT EXISTS "Orders"(
    "order_id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "status" VARCHAR(255) NOT NULL,
    "total_price" NUMERIC(12,2) NOT NULL,
    "created_at" TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL
);
ALTER TABLE "Orders" ADD PRIMARY KEY("order_id");

CREATE TABLE IF NOT EXISTS "Order_items"(
    "id" SERIAL NOT NULL,
    "order_id" INTEGER NOT NULL,
    "product_id" INTEGER NOT NULL,
    "quantity" INTEGER NOT NULL CHECK ("quantity" > 0),
    "price_" NUMERIC(12,2) NOT NULL 
);
ALTER TABLE "Order_items" ADD PRIMARY KEY("id");

ALTER TABLE "Baskets" ADD CONSTRAINT "baskets_user_id_foreign" FOREIGN KEY("user_id") REFERENCES "Users"("user_id");
ALTER TABLE "Comments" ADD CONSTRAINT "comments_product_id_foreign" FOREIGN KEY("product_id") REFERENCES "Products"("product_id");
ALTER TABLE "Comments" ADD CONSTRAINT "comments_user_id_foreign" FOREIGN KEY("user_id") REFERENCES "Users"("user_id");
ALTER TABLE "Baskets_items" ADD CONSTRAINT "baskets_items_product_id_foreign" FOREIGN KEY("product_id") REFERENCES "Products"("product_id");
ALTER TABLE "Order_items" ADD CONSTRAINT "order_items_product_id_foreign" FOREIGN KEY("product_id") REFERENCES "Products"("product_id");
ALTER TABLE "Order_items" ADD CONSTRAINT "order_items_order_id_foreign" FOREIGN KEY("order_id") REFERENCES "Orders"("order_id");
ALTER TABLE "Sellers" ADD CONSTRAINT "sellers_user_id_foreign" FOREIGN KEY("user_id") REFERENCES "Users"("user_id");
ALTER TABLE "Baskets_items" ADD CONSTRAINT "baskets_items_basket_id_foreign" FOREIGN KEY("Basket_id") REFERENCES "Baskets"("basket_id");
ALTER TABLE "Products" ADD CONSTRAINT "products_seller_id_foreign" FOREIGN KEY("seller_id") REFERENCES "Sellers"("seller_id");
ALTER TABLE "Orders" ADD CONSTRAINT "orders_user_id_foreign" FOREIGN KEY("user_id") REFERENCES "Users"("user_id");

--логи и метрики

CREATE TABLE IF NOT EXISTS "Product_views" (
    "id" SERIAL PRIMARY KEY,
    "user_id" INTEGER REFERENCES "Users"("user_id") ON DELETE SET NULL,
    "product_id" INTEGER REFERENCES "Products"("product_id") ON DELETE CASCADE,
    "viewed_at" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Search_queries" (
    "id" SERIAL PRIMARY KEY,
    "user_id" INTEGER REFERENCES "Users"("user_id") ON DELETE SET NULL,
    "query" TEXT NOT NULL,
    "result_count" INTEGER NOT NULL,
    "searched_at" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Cart_actions" (
    "id" SERIAL PRIMARY KEY,
    "user_id" INTEGER REFERENCES "Users"("user_id") ON DELETE CASCADE,
    "product_id" INTEGER REFERENCES "Products"("product_id") ON DELETE CASCADE,
    "action_type" VARCHAR(10) NOT NULL CHECK (action_type IN ('add', 'remove', 'increase', 'decrease')),
    "quantity" INTEGER CHECK (quantity > 0),
    "action_time" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Order_events" (
    "id" SERIAL PRIMARY KEY,
    "user_id" INTEGER REFERENCES "Users"("user_id") ON DELETE CASCADE,
    "order_id" INTEGER REFERENCES "Orders"("order_id") ON DELETE CASCADE,
    "total_price" NUMERIC(12,2) NOT NULL,
    "created_at" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "Auth_events" (
    "id" SERIAL PRIMARY KEY,
    "user_id" INTEGER REFERENCES "Users"("user_id") ON DELETE SET NULL,
    "event_type" VARCHAR(10) NOT NULL CHECK (event_type IN ('login', 'register')),
    "ip_address" TEXT,
    "user_agent" TEXT,
    "event_time" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

