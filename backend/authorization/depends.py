from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from typing import Annotated, Callable
from . import db, security


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

async def get_current_user(token: Annotated[str, Depends(oauth2_scheme)]):
    payload = security.verify_token(token)
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
    print("DEBUG: user from DB =", user)  
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    return user

def require_role(required_roles: list[str]) -> Callable:
    async def role_checker(current_user: Annotated[dict, Depends(get_current_user)]):
        user_role = current_user.get("role")
        if user_role not in required_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not enough permissions"
            )
        return current_user
    return role_checker
