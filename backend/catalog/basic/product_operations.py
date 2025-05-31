from typing import Optional, Dict, Any
from fastapi import HTTPException
from decimal import Decimal
from db import pool
from elastic.sync import sync_product_to_elasticsearch, delete_product_from_elasticsearch

async def create_product(
    seller_id: int,
    product_name: str,
    description: str,
    category: str,
    price: Decimal,
    in_stock: int,
    status: str = "available"
) -> Dict[str, Any]:
    """Create a new product in both PostgreSQL and Elasticsearch"""
    try:
        async with pool.acquire() as conn:
            # Create product in PostgreSQL
            query = '''
                INSERT INTO "Products" (
                    seller_id, product_name, description, 
                    category, price, in_stock, status
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                RETURNING product_id
            '''
            product = await conn.fetchrow(
                query,
                seller_id,
                product_name,
                description,
                category,
                price,
                in_stock,
                status
            )
            
            if not product:
                raise HTTPException(status_code=500, detail="Failed to create product")
            
            # Sync to Elasticsearch
            await sync_product_to_elasticsearch(str(product["product_id"]))
            
            return {"product_id": product["product_id"]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error creating product: {str(e)}")

async def update_product(
    product_id: int,
    seller_id: Optional[int] = None,
    product_name: Optional[str] = None,
    description: Optional[str] = None,
    category: Optional[str] = None,
    price: Optional[Decimal] = None,
    in_stock: Optional[int] = None,
    status: Optional[str] = None
) -> Dict[str, Any]:
    """Update a product in both PostgreSQL and Elasticsearch"""
    try:
        async with pool.acquire() as conn:
            # Check if product exists
            existing = await conn.fetchrow(
                'SELECT product_id FROM "Products" WHERE product_id = $1',
                product_id
            )
            if not existing:
                raise HTTPException(status_code=404, detail="Product not found")

            # Build update query dynamically
            updates = []
            params = [product_id]  # First parameter is always product_id
            param_index = 2  # Start from 2 as $1 is product_id

            if seller_id is not None:
                updates.append(f"seller_id = ${param_index}")
                params.append(seller_id)
                param_index += 1
            if product_name is not None:
                updates.append(f"product_name = ${param_index}")
                params.append(product_name)
                param_index += 1
            if description is not None:
                updates.append(f"description = ${param_index}")
                params.append(description)
                param_index += 1
            if category is not None:
                updates.append(f"category = ${param_index}")
                params.append(category)
                param_index += 1
            if price is not None:
                updates.append(f"price = ${param_index}")
                params.append(price)
                param_index += 1
            if in_stock is not None:
                updates.append(f"in_stock = ${param_index}")
                params.append(in_stock)
                param_index += 1
            if status is not None:
                updates.append(f"status = ${param_index}")
                params.append(status)
                param_index += 1

            if not updates:
                return {"message": "No fields to update"}

            # Execute update query
            query = f'''
                UPDATE "Products"
                SET {", ".join(updates)}
                WHERE product_id = $1
                RETURNING product_id
            '''
            updated = await conn.fetchrow(query, *params)
            
            if not updated:
                raise HTTPException(status_code=500, detail="Failed to update product")
            
            # Sync to Elasticsearch
            await sync_product_to_elasticsearch(str(updated["product_id"]))
            
            return {"product_id": updated["product_id"]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating product: {str(e)}")

async def delete_product(product_id: int) -> Dict[str, Any]:
    """Delete a product from both PostgreSQL and Elasticsearch"""
    try:
        async with pool.acquire() as conn:
            # Check if product exists
            existing = await conn.fetchrow(
                'SELECT product_id FROM "Products" WHERE product_id = $1',
                product_id
            )
            if not existing:
                raise HTTPException(status_code=404, detail="Product not found")

            # Delete product from PostgreSQL
            await conn.execute(
                'DELETE FROM "Products" WHERE product_id = $1',
                product_id
            )
            
            # Delete from Elasticsearch
            await delete_product_from_elasticsearch(str(product_id))
            
            return {"message": "Product deleted successfully"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error deleting product: {str(e)}")
