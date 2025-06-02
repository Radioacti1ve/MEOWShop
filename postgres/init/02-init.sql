INSERT INTO "Users" ("username", "email", "password", "role", "registration_date") VALUES
('ivan_petrov', 'ivan.petrov@example.com', 'hashed_password_1', 'user', '2023-01-15 10:30:00'),
('ekaterina_smirnova', 'ekaterina.smirnova@example.com', 'hashed_password_2', 'user', '2023-02-20 14:15:00'),
('alex_volkov', 'alex.volkov@example.com', 'hashed_password_3', 'user', '2023-03-05 09:45:00'),
('olga_ivanova', 'olga.ivanova@example.com', 'hashed_password_4', 'user', '2023-04-10 16:20:00'),
('dmitry_sokolov', 'dmitry.sokolov@example.com', 'hashed_password_5', 'user', '2023-05-12 11:10:00'),
('tech_gadgets', 'tech.gadgets@example.com', 'hashed_password_s1', 'seller', '2023-01-10 08:00:00'),
('fashion_store', 'fashion.store@example.com', 'hashed_password_s2', 'seller', '2023-01-12 09:30:00'),
('home_appliances', 'home.appliances@example.com', 'hashed_password_s3', 'seller', '2023-02-01 10:15:00'),
('admin', 'admin@example.com', 'hashed_admin_password', 'admin', '2023-01-01 00:00:00');

INSERT INTO "Sellers" ("user_id", "description") VALUES
(6, 'Официальный магазин электроники и гаджетов. Гарантия качества.'),
(7, 'Модная одежда и аксессуары от ведущих брендов.'),
(8, 'Бытовая техника для дома по доступным ценам.');

INSERT INTO "Products" ("seller_id", "product_name", "description", "category", "price", "in_stock", "status") VALUES
(1, 'Смартфон Xiaomi Redmi Note 11', '6.43" FHD+, 128 ГБ, 4 ГБ ОЗУ, 50 Мп камера', 'Электроника', 19999.99, 25, 'available'),
(1, 'Наушники JBL Tune 510BT', 'Беспроводные наушники с 40-часовым временем работы', 'Электроника', 4999.00, 40, 'available'),
(1, 'Умные часы Amazfit Bip U Pro', 'Смарт-часы с SpO2, GPS и 9-дневным аккумулятором', 'Электроника', 8999.50, 15, 'available'),
(2, 'Джинсы Levi''s 501', 'Классические прямые джинсы, синий деним', 'Одежда', 7990.00, 30, 'available'),
(2, 'Футболка мужская Oversize', 'Хлопковая футболка свободного кроя, черная', 'Одежда', 2490.00, 50, 'available'),
(2, 'Платье летнее в цветочек', 'Летнее платье из хлопка с цветочным принтом', 'Одежда', 3990.00, 20, 'available'),
(3, 'Кофемашина De''Longhi ECP 33.21', 'Рожковая кофемашина с капучинатором', 'Бытовая техника', 24990.00, 8, 'available'),
(3, 'Холодильник Beko RCNA400K20W', 'Двухкамерный холодильник с No Frost, 395 л', 'Бытовая техника', 45990.00, 5, 'available'),
(3, 'Пылесос Philips PowerPro Expert', 'Мощность 650 Вт, мешок для пыли 2 л', 'Бытовая техника', 8990.00, 12, 'available'),
(1, 'Power Bank 20000 mAh', 'Универсальный power bank с быстрой зарядкой', 'Электроника', 2990.00, 0, 'out_of_stock');

INSERT INTO "Product_images" ("product_id", "image_filename", "position") VALUES
(1, 'xiaomi_redmi_note_11.jpg', 0),
(1, 'xiaomi_redmi_note_11_alt.jpg', 1),

(2, 'jbl_tune_510bt.jpg', 0),
(2, 'jbl_tune_510bt_alt.jpg', 1),

(3, 'amazfit_bip_u_pro.jpg', 0),
(3, 'amazfit_bip_u_pro_alt.jpg', 1),

(4, 'levis_501_jeans.jpg', 0),
(4, 'levis_501_jeans_back.jpg', 1),

(5, 'tshirt_oversize_black.jpg', 0),
(5, 'tshirt_oversize_black_detail.jpg', 1),

(6, 'summer_dress_floral.jpg', 0),
(6, 'summer_dress_floral_model.jpg', 1),

(7, 'delonghi_ecp_33_21.jpg', 0),
(7, 'delonghi_ecp_33_21_side.jpg', 1),

(8, 'beko_rcna400k20w.jpg', 0),
(8, 'beko_rcna400k20w_inside.jpg', 1),

(9, 'philips_powerpro_expert.jpg', 0),
(9, 'philips_powerpro_expert_parts.jpg', 1),

(10, 'powerbank_20000_mah.jpg', 0),
(10, 'powerbank_20000_mah_ports.jpg', 1);


INSERT INTO "Baskets" ("user_id") VALUES
(1), (2), (3), (4), (5);

INSERT INTO "Baskets_items" ("Basket_id", "product_id", "quantity", "price_") VALUES
(1, 2, 1, 4999.00),
(1, 5, 2, 2490.00),
(2, 1, 1, 19999.99),
(3, 7, 1, 24990.00),
(4, 3, 1, 8999.50),
(4, 6, 1, 3990.00),
(5, 4, 1, 7990.00);

INSERT INTO "Orders" ("user_id", "status", "total_price", "created_at") VALUES
(1, 'completed', 14989.00, '2023-03-10 12:30:00'),
(2, 'processing', 19999.99, '2023-04-05 14:20:00'),
(3, 'shipped', 24990.00, '2023-04-15 09:45:00'),
(4, 'completed', 12989.50, '2023-05-01 16:10:00'),
(1, 'completed', 7990.00, '2023-05-20 11:25:00');

INSERT INTO "Order_items" ("order_id", "product_id", "quantity", "price_") VALUES
(1, 2, 1, 4999.00),
(1, 5, 2, 2490.00),
(2, 1, 1, 19999.99),
(3, 7, 1, 24990.00),
(4, 3, 1, 8999.50),
(4, 6, 1, 3990.00),
(5, 4, 1, 7990.00);

INSERT INTO "Comments" ("user_id", "product_id", "reply_to_comment_id", "text", "rating", "created_at") VALUES
(1, 1, NULL, 'Отличный телефон за свои деньги! Камера на высоте.', 5, '2023-03-12 10:00:00'),
(2, 1, NULL, 'Батарея держит не так долго, как хотелось бы', 3, '2023-03-15 14:30:00'),
(3, 7, NULL, 'Делает вкусный кофе, но шумноватая', 4, '2023-04-20 09:15:00'),
(4, 3, NULL, 'Очень удобные часы, точные показатели здоровья', 5, '2023-05-05 16:45:00'),
(5, 4, NULL, 'Классические джинсы, сидят идеально', 5, '2023-05-25 12:20:00'),
(1, 2, NULL,'Звук отличный, но наушники немного давят', 4, '2023-04-01 11:10:00'),
(3, 1, 1, 'Согласен насчёт камеры! Ещё и процессор мощный', NULL, '2023-03-12 11:30:00'),
(4, 1, 2, 'А у меня батарея держит 2 дня в режиме энергосбережения', NULL, '2023-03-15 18:00:00'),
(2, 7, 3, 'Шум действительно есть, но для такой мощности это нормально', NULL, '2023-04-20 10:45:00'),
(5, 3, 4, 'А как с водонепроницаемостью? Можно плавать?', NULL, '2023-05-05 17:30:00'),
(1, 4, 5, 'Как они после стирки? Не садятся?', NULL, '2023-05-25 13:00:00'),
(2, 2, 6, 'Попробуйте раздвинуть дужки немного шире', NULL, '2023-04-01 12:45:00');