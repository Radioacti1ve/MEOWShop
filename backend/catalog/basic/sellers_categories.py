from fastapi import APIRouter, Query, HTTPException
import db

router = APIRouter(prefix="/catalog", tags=["sellers_categories"])

@router.get("/sellers/")
async def get_sellers(
    sort_by: str | None = Query(None, enum=["rating", "sales"], description="Сортировка: rating или sales")
):
    try:
        async with db.pool.acquire() as conn:
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

            sellers = await conn.fetch(base_query)
            return [dict(record) for record in sellers]

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/categories/")
async def get_categories():
    try:
        async with db.pool.acquire() as conn:
            rows = await conn.fetch('SELECT DISTINCT category FROM "Products" ORDER BY category')
            categories = [row["category"] for row in rows]
            return categories
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
