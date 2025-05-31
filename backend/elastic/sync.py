from typing import Dict, Any, List
import asyncio
from datetime import datetime
import logging
import db
from elastic.client import get_elasticsearch_client
from elastic.mappings import PRODUCT_INDEX_NAME

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def get_all_products() -> List[Dict[str, Any]]:
    """Get all products from PostgreSQL database"""
    try:
        await db.init_db_pool()
        
        async with db.pool.acquire() as conn:
            query = """
                SELECT 
                    p.product_id,
                    p.seller_id,
                    p.product_name,
                    p.description,
                    p.category,
                    p.price,
                    p.in_stock,
                    p.status,
                    u.username AS seller_name,
                    ROUND(AVG(c.rating)::numeric, 2) AS avg_rating
                FROM "Products" p
                JOIN "Sellers" s ON p.seller_id = s.seller_id
                JOIN "Users" u ON s.user_id = u.user_id
                LEFT JOIN "Comments" c ON p.product_id = c.product_id
                GROUP BY p.product_id, u.username
            """
            rows = await conn.fetch(query)
            return [dict(row) for row in rows]
    except Exception as e:
        logger.error(f"Error in get_all_products: {e}")
        raise

async def sync_products_to_elasticsearch():
    """Synchronize all products from PostgreSQL to Elasticsearch"""
    logger.info("Starting synchronization process...")
    
    try:
        await db.init_db_pool()
        
        es_client = get_elasticsearch_client()
        await es_client.initialize()
        logger.info("Elasticsearch client initialized")
        
        from elastic.mappings import create_product_index
        await create_product_index(es_client.get_client())
        logger.info("Index mapping created/updated")

        logger.info("Fetching products from PostgreSQL...")
        products = await get_all_products()
        logger.info(f"Found {len(products)} products in PostgreSQL")

        operations = []
        for product in products:
            product['product_id'] = str(product['product_id'])
            product['seller_id'] = str(product['seller_id'])
            
            if product['price'] is not None:
                product['price'] = float(product['price'])
            
            if product['avg_rating'] is not None:
                product['avg_rating'] = float(product['avg_rating'])

            operations.extend([
                {"index": {"_index": PRODUCT_INDEX_NAME, "_id": product['product_id']}},
                product
            ])

        if operations:
            logger.info(f"Starting bulk indexing of {len(products)} products...")
            response = await es_client.get_client().bulk(body=operations, refresh=True)
            
            if response.get("errors"):
                logger.error("Errors during bulk indexing:")
                for item in response["items"]:
                    if "error" in item["index"]:
                        logger.error(f"Error indexing document {item['index']['_id']}: {item['index']['error']}")
            else:
                logger.info(f"Successfully synchronized {len(products)} products to Elasticsearch")
    except Exception as e:
        logger.error(f"Error in sync_products_to_elasticsearch: {e}")
        raise

async def sync_product_to_elasticsearch(product_id: str):
    """Synchronize a single product to Elasticsearch"""
    try:
        await db.init_db_pool()
        async with db.pool.acquire() as conn:
            query = """
                SELECT 
                    p.product_id,
                    p.seller_id,
                    p.product_name,
                    p.description,
                    p.category,
                    p.price,
                    p.in_stock,
                    p.status,
                    u.username AS seller_name,
                    ROUND(AVG(c.rating)::numeric, 2) AS avg_rating
                FROM "Products" p
                JOIN "Sellers" s ON p.seller_id = s.seller_id
                JOIN "Users" u ON s.user_id = u.user_id
                LEFT JOIN "Comments" c ON p.product_id = c.product_id
                WHERE p.product_id = $1
                GROUP BY p.product_id, u.username
            """
            row = await conn.fetchrow(query, product_id)
            if row:
                product = dict(row)
                
                product['product_id'] = str(product['product_id'])
                product['seller_id'] = str(product['seller_id'])
                
                if product['price'] is not None:
                    product['price'] = float(product['price'])

                es_client = get_elasticsearch_client()
                await es_client.initialize()
                await es_client.get_client().index(
                    index=PRODUCT_INDEX_NAME,
                    id=product['product_id'],
                    document=product,
                    refresh=True
                )
    except Exception as e:
        logger.error(f"Error in sync_product_to_elasticsearch: {e}")
        raise

async def delete_product_from_elasticsearch(product_id: str):
    """Delete a product from Elasticsearch"""
    es_client = get_elasticsearch_client()
    await es_client.initialize()
    try:
        await es_client.get_client().delete(
            index=PRODUCT_INDEX_NAME,
            id=product_id,
            refresh=True
        )
    except Exception:
        pass
