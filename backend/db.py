import asyncpg
import json
from typing import Optional
from redis.asyncio import Redis
import datetime

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

async def init_db_pool():
    global pool
    if pool is None:
        pool = await asyncpg.create_pool(**DB_CONFIG)

async def get_user_by_username(username: str) -> Optional[dict]:
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

