from fastapi import APIRouter, Depends, HTTPException, status
from typing import Annotated
from datetime import datetime

from authorization import db
from authorization.depends import get_current_user

router = APIRouter(prefix="/purchase", tags=["Purchase"])

@router.post("/")
async def purchase_items(current_user: Annotated[dict, Depends(get_current_user)]):
    if current_user["role"] != "user":
        raise HTTPException(status_code=403, detail="Only users can make purchases")

    async with db.pool.acquire() as conn:
        async with conn.transaction():
            basket = await conn.fetchrow(
                'SELECT basket_id FROM "Baskets" WHERE user_id = $1',
                current_user["user_id"]
            )
            if not basket:
                raise HTTPException(status_code=404, detail="Cart not found")

            basket_items = await conn.fetch(
                'SELECT product_id, quantity, price_ FROM "Baskets_items" WHERE "Basket_id" = $1',
                basket["basket_id"]
            )
            if not basket_items:
                raise HTTPException(status_code=400, detail="Cart is empty")

            for item in basket_items:
                product = await conn.fetchrow(
                    'SELECT in_stock, status FROM "Products" WHERE product_id = $1',
                    item["product_id"]
                )
                if not product:
                    raise HTTPException(status_code=404, detail=f"Product {item['product_id']} not found")
                if product["status"] != "available":
                    raise HTTPException(status_code=400, detail=f"Product {item['product_id']} is not available for purchase")
                if product["in_stock"] < item["quantity"]:
                    raise HTTPException(status_code=400, detail=f"Not enough stock for product_id {item['product_id']}")

            total_price = sum(item["price_"] * item["quantity"] for item in basket_items)

            order = await conn.fetchrow(
                'INSERT INTO "Orders" (user_id, status, total_price, created_at) VALUES ($1, $2, $3, $4) RETURNING order_id',
                current_user["user_id"], "confirmed", total_price, datetime.utcnow()
            )
            order_id = order["order_id"]

            for item in basket_items:
                await conn.execute(
                    'INSERT INTO "Order_items" (order_id, product_id, quantity, price_) VALUES ($1, $2, $3, $4)',
                    order_id, item["product_id"], item["quantity"], item["price_"]
                )
                await conn.execute(
                    'UPDATE "Products" SET in_stock = in_stock - $1 WHERE product_id = $2',
                    item["quantity"], item["product_id"]
                )

            await conn.execute(
                'DELETE FROM "Baskets_items" WHERE "Basket_id" = $1',
                basket["basket_id"]
            )

            return {"detail": "Purchase successful", "order_id": order_id, "total_price": float(total_price)}
