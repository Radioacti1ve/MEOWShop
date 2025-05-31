import asyncio
from elastic.sync import sync_products_to_elasticsearch
from db import init_db_pool

async def main():
    # Initialize database pool
    await init_db_pool()
    
    # Sync all products to Elasticsearch
    await sync_products_to_elasticsearch()

if __name__ == "__main__":
    asyncio.run(main())
