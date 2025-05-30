from fastapi import APIRouter, Query
import psycopg2.extras
import db

router = APIRouter(prefix="/api", tags=["sellers_categories"])

@router.get("/sellers/")
def get_sellers(
    sort_by: str = Query(None, enum=["rating", "sales"], description="Сортировка: rating или sales")
):
    conn = db.get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        base_query = '''
            SELECT 
                s.seller_id,
                s.description,
                u.username,
                u.email,
                COALESCE(AVG(c.rating), 0) AS avg_rating,
                COALESCE(SUM(oi.quantity), 0) AS total_sales
            FROM "Sellers" s
            JOIN "Users" u ON s.user_id = u.user_id
            LEFT JOIN "Products" p ON p.seller_id = s.seller_id
            LEFT JOIN "Comments" c ON c.product_id = p.product_id
            LEFT JOIN "Order_items" oi ON oi.product_id = p.product_id
            GROUP BY s.seller_id, s.description, u.username, u.email
        '''

        if sort_by == "rating":
            base_query += " ORDER BY avg_rating DESC"
        elif sort_by == "sales":
            base_query += " ORDER BY total_sales DESC"
        else:
            base_query += " ORDER BY s.seller_id"

        cur.execute(base_query)
        return cur.fetchall()
    finally:
        conn.close()

@router.get("/categories/")
def get_categories():
    conn = db.get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute('SELECT DISTINCT category FROM "Products" ORDER BY category')
        categories = [row[0] for row in cur.fetchall()]
        return categories
    finally:
        conn.close()
