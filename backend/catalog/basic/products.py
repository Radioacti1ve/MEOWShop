from fastapi import APIRouter, Query, HTTPException
from typing import Optional
import psycopg2.extras
import db

router = APIRouter()

@router.get("/products")
async def get_products(
    category: Optional[str] = Query(None),
    min_price: Optional[float] = Query(None, ge=0),
    max_price: Optional[float] = Query(None, ge=0),
    in_stock: Optional[bool] = Query(None),
    min_rating: Optional[float] = Query(None, ge=0, le=5),
    max_rating: Optional[float] = Query(None, ge=0, le=5),
    sort_by: Optional[str] = Query(None),
    seller_id: Optional[int] = Query(None)
):
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
            JOIN "Sellers" s ON p.seller_id = s.seller_id
            JOIN "Users" u ON s.user_id = u.user_id
            LEFT JOIN "Comments" c ON p.product_id = c.product_id
            WHERE TRUE
        '''
        params = []

        if category:
            query += ' AND p.category = %s'
            params.append(category)
        if min_price is not None:
            query += ' AND p.price >= %s'
            params.append(min_price)
        if max_price is not None:
            query += ' AND p.price <= %s'
            params.append(max_price)
        if in_stock is not None:
            if in_stock:
                query += ' AND p.in_stock > 0'
            else:
                query += ' AND p.in_stock = 0'
        if seller_id is not None:
            query += ' AND p.seller_id = %s'
            params.append(seller_id)

        query += ' GROUP BY p.product_id, u.username'

        if min_rating is not None and max_rating is not None:
            query += ' HAVING AVG(c.rating) BETWEEN %s AND %s'
            params.extend([min_rating, max_rating])
        elif min_rating is not None:
            query += ' HAVING AVG(c.rating) >= %s'
            params.append(min_rating)
        elif max_rating is not None:
            query += ' HAVING AVG(c.rating) <= %s'
            params.append(max_rating)

        if sort_by == "price_asc":
            query += ' ORDER BY p.price ASC'
        elif sort_by == "price_desc":
            query += ' ORDER BY p.price DESC'
        elif sort_by == "rating_asc":
            query += ' ORDER BY avg_rating ASC NULLS LAST'
        elif sort_by == "rating_desc":
            query += ' ORDER BY avg_rating DESC NULLS LAST'
        else:
            query += ' ORDER BY p.product_id'

        cur.execute(query, params)
        products = cur.fetchall()
        cur.close()
        conn.close()

        def serialize_product(prod):
            return {
                "product_id": prod["product_id"],
                "seller_id": prod["seller_id"],
                "seller_name": prod["seller_name"],
                "product_name": prod["product_name"],
                "description": prod["description"],
                "category": prod["category"],
                "price": float(prod["price"]),
                "in_stock": prod["in_stock"],
                "status": prod["status"],
                "avg_rating": str(prod["avg_rating"]) if prod["avg_rating"] is not None else "нет оценок"
            }

        return {
            "count": len(products),
            "filters": {
                "category": category,
                "min_price": min_price,
                "max_price": max_price,
                "in_stock": in_stock,
                "min_rating": min_rating,
                "max_rating": max_rating,
                "sort_by": sort_by,
                "seller_id": seller_id
            },
            "products": [serialize_product(p) for p in products]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

