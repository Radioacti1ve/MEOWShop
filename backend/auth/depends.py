from fastapi import Depends, HTTPException, status, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Annotated, Callable, Optional
import db
from .security import oauth2_scheme
from . import security
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def get_current_user(token: Annotated[HTTPAuthorizationCredentials, Depends(oauth2_scheme)]):
    """Get authenticated user from token."""
    try:
        payload = security.verify_token(token.credentials)
        if not payload:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired token",
                headers={"WWW-Authenticate": "Bearer"},
            )
        
        username = payload.get("sub")
        if not username:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token payload",
                headers={"WWW-Authenticate": "Bearer"},
            )

        user = await db.get_user_by_username(username)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        
        return user
    except Exception as e:
        logger.error(f"Authentication error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

def require_role(required_roles: list[str]) -> Callable:
    """Require specific role(s) for endpoint access."""
    async def role_checker(current_user: Annotated[dict, Depends(get_current_user)]):
        user_role = current_user.get("role")
        if user_role not in required_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not enough permissions"
            )
        return current_user
    return role_checker

async def get_current_user_id(
    authorization: Optional[str] = Header(default=None)
) -> Optional[int]:
    if not authorization or not authorization.startswith("Bearer "):
        return None

    token = authorization.removeprefix("Bearer ").strip()
    payload = security.verify_token(token)
    if not payload:
        return None

    username = payload.get("sub")
    if not username:
        return None

    user = await db.get_user_by_username(username)
    if not user or not user.get("is_active", True):
        return None

    return user["user_id"]