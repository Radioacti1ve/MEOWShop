import psycopg2
from psycopg2.extras import RealDictCursor
from typing import Optional, List
from db import get_db_connection

# Управление профилем продавца

def update_seller_profile(user_id: int, description: str) -> Optional[dict]:
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute('UPDATE "Sellers" SET description = %s WHERE user_id = %s RETURNING *', (description, user_id))
        conn.commit()
        seller = cur.fetchone()
        return dict(seller) if seller else None
    finally:
        conn.close()

# Добавление нового товара

def add_product(seller_id: int, product_name: str, description: str, category: str, price: float, in_stock: int) -> dict:
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            'INSERT INTO "Products" (seller_id, product_name, description, category, price, in_stock) '
            'VALUES (%s, %s, %s, %s, %s, %s) RETURNING *',
            (seller_id, product_name, description, category, price, in_stock)
        )
        conn.commit()
        product = cur.fetchone()
        return dict(product)
    finally:
        conn.close()

# Редактирование информации о товаре (только своих)

def update_product(seller_id: int, product_id: int, product_name: Optional[str] = None, description: Optional[str] = None, category: Optional[str] = None, price: Optional[float] = None, in_stock: Optional[int] = None) -> Optional[dict]:
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        # Получаем текущие значения
        cur.execute('SELECT * FROM "Products" WHERE product_id = %s AND seller_id = %s', (product_id, seller_id))
        product = cur.fetchone()
        if not product:
            return None
        # Обновляем только переданные поля
        new_name = product_name if product_name is not None else product['product_name']
        new_desc = description if description is not None else product['description']
        new_cat = category if category is not None else product['category']
        new_price = price if price is not None else product['price']
        new_stock = in_stock if in_stock is not None else product['in_stock']
        cur.execute(
            'UPDATE "Products" SET product_name=%s, description=%s, category=%s, price=%s, in_stock=%s '
            'WHERE product_id=%s AND seller_id=%s RETURNING *',
            (new_name, new_desc, new_cat, new_price, new_stock, product_id, seller_id)
        )
        conn.commit()
        updated = cur.fetchone()
        return dict(updated) if updated else None
    finally:
        conn.close()

# Удаление товара (только своих)

def delete_product(seller_id: int, product_id: int) -> bool:
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute('DELETE FROM "Products" WHERE product_id = %s AND seller_id = %s RETURNING product_id', (product_id, seller_id))
        conn.commit()
        deleted = cur.fetchone()
        return bool(deleted)
    finally:
        conn.close()

def get_orders_with_seller_products(seller_id: int) -> list:
    """
    Получить список заказов, в которых есть товары данного продавца.
    Возвращает список заказов с деталями товаров этого продавца в каждом заказе.
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute('''
            SELECT o.*, oi.product_id, oi.quantity, oi.price_ 
            FROM "Orders" o
            JOIN "Order_items" oi ON o.order_id = oi.order_id
            JOIN "Products" p ON oi.product_id = p.product_id
            WHERE p.seller_id = %s
            ORDER BY o.created_at DESC
        ''', (seller_id,))
        orders = cur.fetchall()
        return [dict(order) for order in orders]
    finally:
        conn.close()


def set_product_status(seller_id: int, product_id: int, status: str) -> Optional[dict]:
    """
    Установить статус товара (например, 'active', 'inactive', 'archived').
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            'UPDATE "Products" SET status = %s WHERE product_id = %s AND seller_id = %s RETURNING *',
            (status, product_id, seller_id)
        )
        conn.commit()
        updated = cur.fetchone()
        return dict(updated) if updated else None
    finally:
        conn.close()


def get_comments_for_seller_products(seller_id: int) -> list:
    """
    Получить все комментарии ко всем товарам продавца.
    """
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute('''
            SELECT c.*, p.product_name FROM "Comments" c
            JOIN "Products" p ON c.product_id = p.product_id
            WHERE p.seller_id = %s
            ORDER BY c.created_at DESC
        ''', (seller_id,))
        comments = cur.fetchall()
        return [dict(comment) for comment in comments]
    finally:
        conn.close()

def bulk_insert_products(seller_id: int, products: list) -> list:
    """
    Массовая вставка товаров в БД. products — список dict с ключами: product_name, description, category, price, in_stock
    """
    conn = get_db_connection()
    inserted = []
    try:
        cur = conn.cursor()
        for product in products:
            cur.execute(
                'INSERT INTO "Products" (seller_id, product_name, description, category, price, in_stock) '
                'VALUES (%s, %s, %s, %s, %s, %s) RETURNING *',
                (seller_id, product["product_name"], product["description"], product["category"], product["price"], product["in_stock"])
            )
            inserted.append(dict(cur.fetchone()))
        conn.commit()
        return inserted
    finally:
        conn.close()


