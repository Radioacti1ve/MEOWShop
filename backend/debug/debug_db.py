import asyncio
from ..elastic.sync import get_all_products
from .. import db

async def main():
    await db.init_db_pool()
    
    products = await get_all_products()
    print(f"Found {len(products)} products in PostgreSQL:")
    for product in products:
        print(f"Product ID: {product['product_id']}, Name: {product['product_name']}")

if __name__ == "__main__":
    asyncio.run(main())
