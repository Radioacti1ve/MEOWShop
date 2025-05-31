import psycopg2
from psycopg2.extras import RealDictCursor
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
