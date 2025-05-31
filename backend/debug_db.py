import asyncio
from elastic.sync import get_all_products
from db import init_db_pool

async def main():
    # Initialize database pool
    await init_db_pool()
    
    # Get products from PostgreSQL
    products = await get_all_products()
    print(f"Found {len(products)} products in PostgreSQL:")
    for product in products:
        print(f"Product ID: {product['product_id']}, Name: {product['product_name']}")

if __name__ == "__main__":
    asyncio.run(main())
