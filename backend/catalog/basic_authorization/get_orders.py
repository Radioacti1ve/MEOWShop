from fastapi import APIRouter, Depends, HTTPException, Query, status
from typing import Annotated, List, Dict, Any
from datetime import date
import logging
import db
from auth.depends import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(tags=["Orders"])

@router.get("/orders")
async def get_orders(
    current_user: Annotated[dict, Depends(get_current_user)],
    user_id: int | None = Query(None, description="User ID to fetch orders for (admin only)"),
    min_price: float | None = Query(None, description="Minimum total price"),
    max_price: float | None = Query(None, description="Maximum total price"),
    start_date: date | None = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: date | None = Query(None, description="End date (YYYY-MM-DD)"),
    limit: int = Query(20, ge=1, le=100, description="Max number of orders to return"),
    offset: int = Query(0, ge=0, description="Number of orders to skip")
):
    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    role = current_user.get("role")
    current_id = current_user.get("user_id")

    print(f"User ID: {current_id}, Role: {role}, Requested user_id: {user_id}")

    if role == "admin":
        target_user_id = user_id if user_id is not None else current_id
    else:
        if user_id is not None and user_id != current_id:
            raise HTTPException(
                status_code=403,
                detail=f"You cannot view orders of other users. Your role: {role}"
            )
        target_user_id = current_id

    filters = ['user_id = $1']
    values = [target_user_id]
    param_index = 2

    if min_price is not None:
        filters.append(f"total_price >= ${param_index}")
        values.append(min_price)
        param_index += 1

    if max_price is not None:
        filters.append(f"total_price <= ${param_index}")
        values.append(max_price)
        param_index += 1

    if start_date is not None:
        filters.append(f"created_at::date >= ${param_index}")
        values.append(start_date)
        param_index += 1

    if end_date is not None:
        filters.append(f"created_at::date <= ${param_index}")
        values.append(end_date)
        param_index += 1

    where_clause = ' AND '.join(filters)

    async with db.pool.acquire() as conn:
        orders = await conn.fetch(f'''
            SELECT order_id, status, total_price, created_at
            FROM "Orders"
            WHERE {where_clause}
            ORDER BY created_at DESC
            LIMIT {limit} OFFSET {offset}
        ''', *values)

        if not orders:
            return {"orders": []}

        order_ids = [order["order_id"] for order in orders]

        order_items = await conn.fetch('''
            SELECT oi.order_id, p.product_name, oi.quantity, oi.price_
            FROM "Order_items" oi
            JOIN "Products" p ON oi.product_id = p.product_id
            WHERE oi.order_id = ANY($1::int[])
        ''', order_ids)

        order_items_map = {}
        for item in order_items:
            order_id = item["order_id"]
            order_items_map.setdefault(order_id, []).append({
                "product_name": item["product_name"],
                "quantity": item["quantity"],
                "price": float(item["price_"])
            })

        result = []
        for order in orders:
            result.append({
                "order_id": order["order_id"],
                "status": order["status"],
                "total_price": float(order["total_price"]),
                "created_at": order["created_at"].isoformat(),
                "items": order_items_map.get(order["order_id"], [])
            })

        return {"orders": result}
