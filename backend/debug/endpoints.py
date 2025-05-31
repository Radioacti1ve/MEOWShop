from fastapi import APIRouter
from elastic.sync import sync_products_to_elasticsearch, get_all_products
import db

router = APIRouter(
    prefix="/debug",
    tags=["debug"],
    responses={404: {"description": "Not found"}},
)

@router.get("/sync")
async def debug_sync():
    """Force synchronization with Elasticsearch"""
    try:
        # Make sure DB pool is initialized
        await db.init_db_pool()
        
        # Perform synchronization
        await sync_products_to_elasticsearch()
        return {"message": "Synchronization completed"}
    except Exception as e:
        import traceback
        print("Error during sync:", str(e))
        print("Traceback:", traceback.format_exc())
        return {"error": str(e), "type": type(e).__name__}

@router.get("/test-db")
async def test_db_connection():
    """Test database connection and check tables"""
    try:
        await db.init_db_pool()
        results = {}
        
        async with db.pool.acquire() as conn:
            # Check Products table
            products = await conn.fetch('SELECT COUNT(*) as count FROM "Products"')
            results["products_count"] = products[0]["count"]
            
            # Check Sellers table
            sellers = await conn.fetch('SELECT COUNT(*) as count FROM "Sellers"')
            results["sellers_count"] = sellers[0]["count"]
            
            # Check Users table
            users = await conn.fetch('SELECT COUNT(*) as count FROM "Users"')
            results["users_count"] = users[0]["count"]
            
            # Check PendingSellers table
            pending = await conn.fetch('SELECT COUNT(*) as count FROM "PendingSellers"')
            results["pending_sellers_count"] = pending[0]["count"]
            
            # Get sample pending seller
            sample_pending = await conn.fetch('SELECT * FROM "PendingSellers" LIMIT 1')
            if sample_pending:
                results["sample_pending_seller"] = dict(sample_pending[0])
            
            # Get sample product
            sample = await conn.fetch('SELECT * FROM "Products" LIMIT 1')
            if sample:
                results["sample_product"] = dict(sample[0])
            
        return {
            "status": "connected",
            "counts": results
        }
    except Exception as e:
        import traceback
        print("Database test error:", str(e))
        print("Traceback:", traceback.format_exc())
        return {
            "status": "error",
            "error": str(e),
            "type": type(e).__name__
        }

@router.get("/postgres")
async def debug_postgres():
    """Get all products from PostgreSQL for debugging"""
    products = await get_all_products()
    return {
        "count": len(products),
        "products": products
    } 