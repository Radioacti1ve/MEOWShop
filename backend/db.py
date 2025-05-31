import asyncpg
import json
from typing import Optional, List
from redis.asyncio import Redis
import datetime
import asyncio
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DB_CONFIG = {
    "user": "postgres",
    "password": "123",
    "database": "meowshop",
    "host": "db",
    "port": 5432
}

redis_client = Redis(host='redis', port=6379, decode_responses=True)

pool: asyncpg.pool.Pool | None = None

def default_serializer(obj):
    if isinstance(obj, datetime.datetime):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")

async def init_db_pool(max_retries=5, retry_interval=5):
    """Initialize database pool with retries"""
    global pool
    if pool is not None:
        return pool

    for attempt in range(max_retries):
        try:
            logger.info(f"Attempting to create database pool (attempt {attempt + 1}/{max_retries})")
            pool = await asyncpg.create_pool(**DB_CONFIG)
            
            async with pool.acquire() as conn:
                await conn.fetchval('SELECT 1')
            
            logger.info("Successfully connected to the database")
            return pool
        except Exception as e:
            logger.error(f"Failed to initialize database pool (attempt {attempt + 1}): {str(e)}")
            if attempt < max_retries - 1:
                logger.info(f"Retrying in {retry_interval} seconds...")
                await asyncio.sleep(retry_interval)
            else:
                logger.error("Max retries reached, could not initialize database pool")
                raise

async def close_db_pool():
    """Close the database pool"""
    global pool
    if pool:
        await pool.close()
        pool = None

async def get_user_by_username(username: str) -> Optional[dict]:
    global pool
    if pool is None:
        await init_db_pool()

    cache_key = f"user:{username}"
    cached = await redis_client.get(cache_key)
    if cached:
        return json.loads(cached)
    
    async with pool.acquire() as conn:
        user = await conn.fetchrow('SELECT * FROM "Users" WHERE username = $1', username)
        if user:
            user_dict = dict(user)
            await redis_client.set(cache_key, json.dumps(user_dict, default=default_serializer), ex=3600)
            return user_dict
        return None

async def create_user(username: str, email: str, hashed_password: str, role: str = "user") -> Optional[dict]:
    global pool
    if pool is None:
        await init_db_pool()

    async with pool.acquire() as conn:
        user = await conn.fetchrow(
            'INSERT INTO "Users" (username, email, password, role) '
            'VALUES ($1, $2, $3, $4) RETURNING *',
            username, email, hashed_password, role
        )
        if user:
            cache_key = f"user:{username}"
            await redis_client.delete(cache_key)
            return dict(user)
        return None

async def create_pending_seller(user_id: int) -> Optional[dict]:
    """Create a new pending seller application"""
    global pool
    if pool is None:
        await init_db_pool()

    async with pool.acquire() as conn:
        try:
            seller = await conn.fetchrow(
                '''
                INSERT INTO "PendingSellers" (user_id)
                VALUES ($1)
                RETURNING *
                ''',
                user_id
            )
            
            return dict(seller) if seller else None

        except asyncpg.UniqueViolationError:
            return None

async def get_pending_seller(pending_seller_id: int) -> Optional[dict]:
    """Get pending seller by ID"""
    global pool
    if pool is None:
        await init_db_pool()

    async with pool.acquire() as conn:
        seller = await conn.fetchrow(
            '''
            SELECT *
            FROM "PendingSellers"
            WHERE pending_seller_id = $1
            ''',
            pending_seller_id
        )
        return dict(seller) if seller else None

async def get_pending_sellers_by_status(status: str) -> List[dict]:
    """Get all pending sellers with specified status"""
    global pool
    if pool is None:
        await init_db_pool()

    async with pool.acquire() as conn:
        sellers = await conn.fetch(
            '''
            SELECT ps.*, u.username, u.email
            FROM "PendingSellers" ps
            JOIN "Users" u ON ps.user_id = u.user_id
            WHERE ps.status = $1
            ORDER BY ps.created_at DESC
            ''',
            status
        )
        return [dict(seller) for seller in sellers]

async def update_pending_seller_status(
    pending_seller_id: int,
    status: str,
    admin_comment: Optional[str] = None
) -> Optional[dict]:
    """Update pending seller status"""
    global pool
    if pool is None:
        await init_db_pool()

    async with pool.acquire() as conn:
        async with conn.transaction():
            seller = await conn.fetchrow(
                '''
                SELECT *
                FROM "PendingSellers"
                WHERE pending_seller_id = $1
                ''',
                pending_seller_id
            )
            
            if not seller:
                return None

            updated_seller = await conn.fetchrow(
                '''
                UPDATE "PendingSellers"
                SET status = $1, admin_comment = $2
                WHERE pending_seller_id = $3
                RETURNING *
                ''',
                status, admin_comment, pending_seller_id
            )
            
            if not updated_seller:
                return None

            if status == 'approved':
                await conn.execute(
                    'UPDATE "Users" SET role = $1 WHERE user_id = $2',
                    'seller', seller['user_id']
                )
                
                await conn.execute(
                    '''
                    INSERT INTO "Sellers" (user_id)
                    VALUES ($1)
                    ''',
                    seller['user_id']
                )

            return dict(updated_seller)

async def get_pending_seller_by_user_id(user_id: int) -> Optional[dict]:
    """Get pending seller application by user ID"""
    global pool
    if pool is None:
        await init_db_pool()

    async with pool.acquire() as conn:
        seller = await conn.fetchrow(
            '''
            SELECT *
            FROM "PendingSellers"
            WHERE user_id = $1
            ''',
            user_id
        )
        return dict(seller) if seller else None

async def create_pending_admin(user_id: int) -> dict:
    """Create a pending admin application"""
    query = '''
        INSERT INTO pending_admins (user_id)
        VALUES ($1)
        RETURNING *
    '''
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, user_id)
        return dict(row) if row else None

async def get_pending_admin_by_id(pending_admin_id: int) -> dict:
    """Get a pending admin application by ID"""
    query = 'SELECT * FROM pending_admins WHERE pending_admin_id = $1'
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, pending_admin_id)
        return dict(row) if row else None

async def get_pending_admins_by_status(status: str) -> list:
    """Get all pending admin applications with given status"""
    query = 'SELECT * FROM pending_admins WHERE status = $1'
    async with pool.acquire() as conn:
        rows = await conn.fetch(query, status)
        return [dict(row) for row in rows]

async def update_pending_admin_status(
    pending_admin_id: int,
    status: str,
    approver_comment: str = None
) -> dict:
    """Update the status of a pending admin application"""
    query = '''
        UPDATE pending_admins
        SET status = $1, approver_comment = $2
        WHERE pending_admin_id = $3
        RETURNING *
    '''
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, status, approver_comment, pending_admin_id)
        if row and status == 'approved':
            await add_role_to_user(dict(row)['user_id'], 'admin')
        return dict(row) if row else None

async def get_pending_admin_by_user_id(user_id: int) -> dict:
    """Get the most recent pending admin application for a user"""
    query = '''
        SELECT * FROM pending_admins 
        WHERE user_id = $1 
        ORDER BY created_at DESC 
        LIMIT 1
    '''
    async with pool.acquire() as conn:
        row = await conn.fetchrow(query, user_id)
        return dict(row) if row else None

async def add_role_to_user(user_id: int, role: str) -> bool:
    """Update user role"""
    async with pool.acquire() as conn:
        result = await conn.execute(
            'UPDATE "Users" SET role = $1 WHERE user_id = $2',
            role, user_id
        )
        return result == "UPDATE 1"

