from fastapi import APIRouter, HTTPException
import psycopg2.extras
import db

router = APIRouter()

@router.get("/products/{product_id}")
async def get_product(product_id: int):
    try:
        conn = db.get_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

        query = '''
            SELECT
                p.product_id,
                p.seller_id,
                u.username AS seller_name,
                p.product_name,
                p.description,
                p.category,
                p.price,
                p.in_stock,
                p.status,
                ROUND(AVG(c.rating)::numeric, 2) AS avg_rating
            FROM "Products" p
            INNER JOIN "Sellers" s ON p.seller_id = s.seller_id
            INNER JOIN "Users" u ON s.user_id = u.user_id
            LEFT JOIN "Comments" c ON p.product_id = c.product_id
            WHERE p.product_id = %s
            GROUP BY p.product_id, u.username
            LIMIT 1
        '''

        cur.execute(query, (product_id,))
        product = cur.fetchone()
        cur.close()
        conn.close()

        if not product:
            raise HTTPException(status_code=404, detail="Товар не найден")

        avg_rating = product["avg_rating"] if product["avg_rating"] is not None else "нет оценок"

        product_info = {
            "product_id": product["product_id"],
            "seller_id": product["seller_id"],
            "seller_name": product["seller_name"],
            "product_name": product["product_name"],
            "description": product["description"],
            "category": product["category"],
            "price": float(product["price"]),  
            "in_stock": product["in_stock"],
            "status": product["status"],
            "avg_rating": str(avg_rating)
        }

        return product_info

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
