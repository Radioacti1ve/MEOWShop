CREATE TABLE IF NOT EXISTS "Users"(
    "user_id" SERIAL,
    "username" VARCHAR(255) NOT NULL,
    "email" VARCHAR(255) NOT NULL UNIQUE,
    "password" VARCHAR(255) NOT NULL,
    "role" VARCHAR(255) DEFAULT 'user',
    "registration_date" TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
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
ALTER TABLE "Products" ADD COLUMN "image_filename" VARCHAR(255);
ALTER TABLE "Products" ADD PRIMARY KEY("product_id");

CREATE TABLE IF NOT EXISTS "Product_images" ( 
    "image_id" SERIAL PRIMARY KEY,
    "product_id" INTEGER,
    "image_filename" VARCHAR(255),
    "position" INTEGER DEFAULT 0,
    FOREIGN KEY ("product_id") REFERENCES "Products"("product_id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "Sellers"(
    "seller_id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "description" TEXT
);
ALTER TABLE "Sellers" ADD PRIMARY KEY("seller_id");

CREATE TABLE IF NOT EXISTS "Comments"(
    "comment_id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
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