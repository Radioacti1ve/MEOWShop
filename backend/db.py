import psycopg2
from psycopg2.extras import RealDictCursor
import asyncpg
from typing import Optional

DB_CONFIG = {
    "dbname": "meowshop",
    "user": "postgres",
    "password": "postgres",
    "host": "db",
    "port": "5432"
}

def get_db_connection():
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)

async def get_async_db_pool():
    """Создает и возвращает пул асинхронных подключений к БД"""
    return await asyncpg.create_pool(
        database=DB_CONFIG["dbname"],
        user=DB_CONFIG["user"],
        password=DB_CONFIG["password"],
        host=DB_CONFIG["host"],
        port=DB_CONFIG["port"]
    )

# Глобальный пул соединений для многократного использования
_pool = None

async def get_async_pool():
    """Возвращает глобальный пул соединений, создавая его при необходимости"""
    global _pool
    if _pool is None:
        _pool = await get_async_db_pool()
    return _pool

def get_user_by_username(username: str) -> Optional[dict]:
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute('SELECT * FROM "Users" WHERE username = %s', (username,))
        user = cur.fetchone()
        return dict(user) if user else None
    finally:
        conn.close()

def create_user(username: str, email: str, hashed_password: str, role: str = "user"):
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            'INSERT INTO "Users" (username, email, password, role) '
            'VALUES (%s, %s, %s, %s) RETURNING *',
            (username, email, hashed_password, role)
        )
        conn.commit()
        user = cur.fetchone()
        return dict(user)
    finally:
        conn.close()
