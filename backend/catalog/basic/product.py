from fastapi import APIRouter, HTTPException, status, Depends
from typing import Optional, Dict, Any
import db
import logging
from auth.depends import get_current_user_id

logger = logging.getLogger(__name__)
router = APIRouter(tags=["Products"])

AVG_RATING_CACHE_PREFIX = "product_avg_rating:"
CACHE_TTL_SECONDS = 3600 

async def get_avg_rating_cache(product_id: int) -> str | None:
    key = AVG_RATING_CACHE_PREFIX + str(product_id)
    cached = await db.redis_client.get(key)
    return cached

async def set_avg_rating_cache(product_id: int, avg_rating: float | None):
    key = AVG_RATING_CACHE_PREFIX + str(product_id)
    value = str(round(avg_rating, 2)) if avg_rating is not None else "нет оценок"
    await db.redis_client.set(key, value)
    await db.redis_client.expire(key, CACHE_TTL_SECONDS)

@router.get("/product/{product_id}", description="Get detailed information about a specific product")
async def get_product(product_id: int, user_id: Optional[int] = Depends(get_current_user_id)):
    try:
        async with db.pool.acquire() as conn:
            await conn.execute(
                '''
                INSERT INTO "Product_views"(user_id, product_id)
                VALUES ($1, $2)
                ''',
                user_id, product_id
            )

        cached_rating = await get_avg_rating_cache(product_id)
        avg_rating = None if cached_rating is None else cached_rating

        async with db.pool.acquire() as conn:
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
                INNER JOIN "Sellers" s ON p.seller_id = s.seller_id
                INNER JOIN "Users" u ON s.user_id = u.user_id
                LEFT JOIN "Comments" c ON p.product_id = c.product_id
                WHERE p.product_id = $1
                GROUP BY p.product_id, u.username
                LIMIT 1
            '''
            product = await conn.fetchrow(query, product_id)

            images_query = '''
                SELECT image_filename
                FROM "Product_images"
                WHERE product_id = $1
                ORDER BY position ASC
            '''
            images_records = await conn.fetch(images_query, product_id)
            image_urls = [
                f"http://localhost:9000/product-images/{r['image_filename']}"
                for r in images_records
                if r["image_filename"]
            ]

        if not product:
            raise HTTPException(status_code=404, detail="Товар не найден")

        if avg_rating is None:
            db_avg = product["avg_rating"]
            avg_rating = str(db_avg) if db_avg is not None else "нет оценок"
            await set_avg_rating_cache(product_id, product["avg_rating"])

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
            "avg_rating": avg_rating,
            "images": image_urls
        }

        return product_info

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
