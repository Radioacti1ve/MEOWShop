from fastapi import APIRouter, Query, HTTPException, Depends, status
from typing import Optional, Annotated, Dict, Any
import db
import logging
from auth.depends import get_current_user

router = APIRouter(tags=["Products"])

redis_client = db.redis_client
logger = logging.getLogger(__name__)

CACHE_TTL_SECONDS = 300  

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
        query = '''
            SELECT
                p.product_id,
                p.seller_id,
                u.username AS seller_name,
                p.product_name,
                p.description,
                p.category,
                p.price,
                p.status,
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
            query += ' AND p.category = $' + str(len(params) + 1)
            params.append(category)
        if min_price is not None:
            query += ' AND p.price >= $' + str(len(params) + 1)
            params.append(min_price)
        if max_price is not None:
            query += ' AND p.price <= $' + str(len(params) + 1)
            params.append(max_price)
        if in_stock is not None:
            if in_stock:
                query += ' AND p.in_stock > 0'
            else:
                query += ' AND p.in_stock = 0'
        if seller_id is not None:
            query += ' AND p.seller_id = $' + str(len(params) + 1)
            params.append(seller_id)

        query += ' GROUP BY p.product_id, u.username'

        if min_rating is not None and max_rating is not None:
            query += ' HAVING AVG(c.rating) BETWEEN $' + str(len(params) + 1) + ' AND $' + str(len(params) + 2)
            params.extend([min_rating, max_rating])
        elif min_rating is not None:
            query += ' HAVING AVG(c.rating) >= $' + str(len(params) + 1)
            params.append(min_rating)
        elif max_rating is not None:
            query += ' HAVING AVG(c.rating) <= $' + str(len(params) + 1)
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

        async with db.pool.acquire() as conn:
            records = await conn.fetch(query, *params)

        async def get_cached_rating(product_id: int, db_rating) -> str:
            cache_key = f"product:{product_id}:avg_rating"
            cached = await redis_client.get(cache_key)
            if cached is not None:
                return cached
            # Если в кеше нет, кешируем то, что пришло из базы (если рейтинг None, то "нет оценок")
            rating_str = str(db_rating) if db_rating is not None else "нет оценок"
            if db_rating is not None:
                await redis_client.set(cache_key, rating_str, ex=CACHE_TTL_SECONDS)
            return rating_str

        products = []
        for p in records:
            avg_rating = await get_cached_rating(p["product_id"], p["avg_rating"])
            products.append({
                "product_id": p["product_id"],
                "seller_id": p["seller_id"],
                "seller_name": p["seller_name"],
                "product_name": p["product_name"],
                "description": p["description"],
                "category": p["category"],
                "price": float(p["price"]),
                "in_stock": p["in_stock"],
                "status": p["status"],
                "avg_rating": avg_rating
            })

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
            "products": products
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal error: {e}")
