from fastapi import APIRouter, Depends, HTTPException, status
from typing import Annotated, List, Dict, Any
import logging
import db
from auth.depends import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(
    prefix="/cart",
    tags=["Cart"]
)

@router.get("/")
async def get_cart(current_user: Annotated[dict, Depends(get_current_user)]):
    async with db.pool.acquire() as conn:
        basket = await conn.fetchrow(
            'SELECT basket_id FROM "Baskets" WHERE user_id = $1',
            current_user["user_id"]
        )
        if not basket:
            return {"items": []}

        items = await conn.fetch(
            '''
            SELECT bi.id, bi.product_id, p.product_name, bi.quantity, bi.price_
            FROM "Baskets_items" bi
            JOIN "Products" p ON bi.product_id = p.product_id
            WHERE bi."Basket_id" = $1
            ''',
            basket["basket_id"]
        )
        return {"items": [dict(item) for item in items]}


@router.post("/add")
async def add_to_cart(
    product_id: int,
    quantity: int,
    current_user: Annotated[dict, Depends(get_current_user)]
):
    if quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be greater than 0")

    async with db.pool.acquire() as conn:
        async with conn.transaction():
            basket = await conn.fetchrow(
                'SELECT basket_id FROM "Baskets" WHERE user_id = $1',
                current_user["user_id"]
            )
            if not basket:
                basket = await conn.fetchrow(
                    'INSERT INTO "Baskets" (user_id) VALUES ($1) RETURNING basket_id',
                    current_user["user_id"]
                )
            basket_id = basket["basket_id"]

            product = await conn.fetchrow(
                'SELECT price, in_stock FROM "Products" WHERE product_id = $1',
                product_id
            )
            if not product:
                raise HTTPException(status_code=404, detail="Product not found")
            if product["in_stock"] < quantity:
                raise HTTPException(status_code=400, detail="Not enough stock")

            existing = await conn.fetchrow(
                'SELECT id, quantity FROM "Baskets_items" WHERE "Basket_id" = $1 AND product_id = $2',
                basket_id, product_id
            )
            if existing:
                new_quantity = existing["quantity"] + quantity
                await conn.execute(
                    'UPDATE "Baskets_items" SET quantity = $1 WHERE id = $2',
                    new_quantity, existing["id"]
                )
            else:
                await conn.execute(
                    'INSERT INTO "Baskets_items" ("Basket_id", product_id, quantity, price_) '
                    'VALUES ($1, $2, $3, $4)',
                    basket_id, product_id, quantity, product["price"]
                )

            await conn.execute(
                '''
                INSERT INTO "Cart_actions" (user_id, product_id, action_type, quantity)
                VALUES ($1, $2, 'add', $3)
                ''',
                current_user["user_id"], product_id, quantity
            )

            return {"detail": "Product added to cart"}


@router.delete("/remove")
async def remove_from_cart(
    product_id: int,
    current_user: Annotated[dict, Depends(get_current_user)]
):
    async with db.pool.acquire() as conn:
        basket = await conn.fetchrow(
            'SELECT basket_id FROM "Baskets" WHERE user_id = $1',
            current_user["user_id"]
        )
        if not basket:
            raise HTTPException(status_code=404, detail="Cart not found")

        result = await conn.execute(
            'DELETE FROM "Baskets_items" WHERE "Basket_id" = $1 AND product_id = $2',
            basket["basket_id"], product_id
        )
        if result == "DELETE 0":
            raise HTTPException(status_code=404, detail="Product not found in cart")
        
        await conn.execute(
            '''
            INSERT INTO "Cart_actions" (user_id, product_id, action_type, quantity)
            VALUES ($1, $2, 'remove', 1)
            ''',
            current_user["user_id"], product_id
        )

        return {"detail": "Product removed from cart"}
    
@router.patch("/increase")
async def increase_quantity(
    product_id: int,
    quantity: int,
    current_user: Annotated[dict, Depends(get_current_user)]
):
    if quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be greater than 0")

    async with db.pool.acquire() as conn:
        async with conn.transaction():
            basket = await conn.fetchrow(
                'SELECT basket_id FROM "Baskets" WHERE user_id = $1',
                current_user["user_id"]
            )
            if not basket:
                raise HTTPException(status_code=404, detail="Cart not found")

            item = await conn.fetchrow(
                'SELECT id, quantity FROM "Baskets_items" WHERE "Basket_id" = $1 AND product_id = $2',
                basket["basket_id"], product_id
            )
            if not item:
                raise HTTPException(status_code=404, detail="Product not in cart")

            product = await conn.fetchrow(
                'SELECT in_stock FROM "Products" WHERE product_id = $1',
                product_id
            )
            if not product:
                raise HTTPException(status_code=404, detail="Product not found")

            if item["quantity"] + quantity > product["in_stock"]:
                raise HTTPException(status_code=400, detail="Not enough stock available")

            await conn.execute(
                'UPDATE "Baskets_items" SET quantity = quantity + $1 WHERE id = $2',
                quantity, item["id"]
            )

            await conn.execute(
                '''
                INSERT INTO "Cart_actions" (user_id, product_id, action_type, quantity)
                VALUES ($1, $2, 'increase', $3)
                ''',
                current_user["user_id"], product_id, quantity
            )

            return {"detail": f"Quantity increased by {quantity}"}
        
@router.patch("/decrease")
async def decrease_quantity(
    product_id: int,
    quantity: int,
    current_user: Annotated[dict, Depends(get_current_user)]
):
    if quantity <= 0:
        raise HTTPException(status_code=400, detail="Quantity must be greater than 0")

    async with db.pool.acquire() as conn:
        async with conn.transaction():
            basket = await conn.fetchrow(
                'SELECT basket_id FROM "Baskets" WHERE user_id = $1',
                current_user["user_id"]
            )
            if not basket:
                raise HTTPException(status_code=404, detail="Cart not found")

            item = await conn.fetchrow(
                'SELECT id, quantity FROM "Baskets_items" WHERE "Basket_id" = $1 AND product_id = $2',
                basket["basket_id"], product_id
            )
            if not item:
                raise HTTPException(status_code=404, detail="Product not in cart")

            new_quantity = item["quantity"] - quantity

            await conn.execute(
                '''
                INSERT INTO "Cart_actions" (user_id, product_id, action_type, quantity)
                VALUES ($1, $2, 'decrease', $3)
                ''',
                current_user["user_id"], product_id, quantity
            )
            
            if new_quantity > 0:
                await conn.execute(
                    'UPDATE "Baskets_items" SET quantity = $1 WHERE id = $2',
                    new_quantity, item["id"]
                )
                return {"detail": f"Quantity decreased by {quantity}"}
            else:
                await conn.execute(
                    'DELETE FROM "Baskets_items" WHERE id = $1',
                    item["id"]
                )
                return {"detail": "Product removed from cart due to zero quantity"}


