from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, HTTPBearer
from .models import UserLogin, UserRegister, Token, TokenRefresh, SellerRegister, PendingSellerResponse, SellerApproval
from . import security
import db
import logging
from typing import Annotated, List
from datetime import datetime
from depends import get_current_user, require_role

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"],
    responses={404: {"description": "Not found"}},
)

security_scheme = HTTPBearer()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")

@router.post("/login", response_model=Token, summary="User login")
async def login(user: UserLogin):
    """
    Login for existing users.
    
    - **username**: Username
    - **password**: Password
    """
    try:
        db_user = await db.get_user_by_username(user.username)
        if not db_user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password"
            )
        if not security.verify_password(user.password, db_user["password"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password"
            )
        
        access_token, refresh_token, expires_in = security.create_tokens({"sub": user.username})
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "expires_in": expires_in
        }
    except HTTPException as http_ex:
        logger.error(f"Login authentication error: {str(http_ex)}")
        raise http_ex
    except Exception as e:
        logger.error(f"Login error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/register", status_code=status.HTTP_201_CREATED, summary="Register new user")
async def register(user: UserRegister):
    """
    Register a new user.
    
    - **username**: Unique username
    - **email**: Valid email address
    - **password**: Strong password
    """
    try:
        existing_user = await db.get_user_by_username(user.username)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )
        hashed_password = security.get_password_hash(user.password)
        new_user = await db.create_user(user.username, user.email, hashed_password)
        return {"message": "User created successfully", "user_id": new_user["user_id"]}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Registration error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.get("/me", summary="Get current user")
async def get_current_user(token: Annotated[str, Depends(oauth2_scheme)]):
    """
    Get information about the currently authenticated user.
    """
    try:
        payload = security.verify_token(token)
        if not payload:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token"
            )
        username = payload.get("sub")
        user = await db.get_user_by_username(username)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        user_data = dict(user)
        del user_data["password"]  # Remove sensitive information
        return user_data
    except HTTPException as e:
        logger.error(f"Authentication error: {str(e)}")
        raise e
    except Exception as e:
        logger.error(f"Get current user error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

@router.post("/refresh", response_model=Token, summary="Refresh access token")
async def refresh_token(token: TokenRefresh):
    """
    Get a new access token using a refresh token.
    
    - **refresh_token**: A valid refresh token
    """
    try:
        payload = security.verify_token(token.refresh_token, token_type="refresh")
        access_token, refresh_token, expires_in = security.create_tokens({"sub": payload["sub"]})
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "expires_in": expires_in
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Token refresh error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/logout", status_code=status.HTTP_200_OK, summary="Logout user")
async def logout(token: Annotated[str, Depends(oauth2_scheme)]):
    """
    Logout the current user by blacklisting their token.
    """
    try:
        payload = security.verify_token(token)
        exp = payload.get("exp", 0)
        now = datetime.utcnow().timestamp()
        ttl = int(exp - now)
        if ttl > 0:
            security.blacklist_token(token, ttl)
        return {"message": "Successfully logged out"}
    except Exception as e:
        logger.error(f"Logout error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/sellers/register", status_code=status.HTTP_201_CREATED, response_model=PendingSellerResponse)
async def register_seller(seller: SellerRegister):
    """
    Register a new seller. Creates a user account and a pending seller application.
    The application must be approved by an admin before the seller can start selling.
    
    - **username**: Unique username
    - **email**: Valid email address
    - **password**: Strong password
    - **company_name**: Name of the company
    - **contact_phone**: Contact phone number
    - **tax_number**: Company tax identification number
    - **documents_url**: Optional URL to company documents
    """
    try:
        # Check if username already exists
        existing_user = await db.get_user_by_username(seller.username)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )

        # Create user account
        hashed_password = security.get_password_hash(seller.password)
        new_user = await db.create_user(seller.username, seller.email, hashed_password)
        if not new_user:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create user account"
            )

        # Create pending seller application
        pending_seller = await db.create_pending_seller(
            user_id=new_user["user_id"],
            company_name=seller.company_name,
            contact_phone=seller.contact_phone,
            tax_number=seller.tax_number,
            documents_url=seller.documents_url
        )
        if not pending_seller:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create seller application"
            )

        return pending_seller

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Seller registration error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.get("/sellers/pending", response_model=List[PendingSellerResponse])
async def get_pending_sellers(
    current_user: Annotated[dict, Depends(require_role(["admin"]))]
):
    """
    Get all pending seller applications.
    Only accessible by admins.
    """
    try:
        return await db.get_pending_sellers_by_status("pending")
    except Exception as e:
        logger.error(f"Error getting pending sellers: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/sellers/{pending_seller_id}/approve", response_model=PendingSellerResponse)
async def approve_seller(
    pending_seller_id: int,
    approval: SellerApproval,
    current_user: Annotated[dict, Depends(require_role(["admin"]))]
):
    """
    Approve or reject a pending seller application.
    Only accessible by admins.
    
    - **status**: Either 'approved' or 'rejected'
    - **admin_comment**: Optional comment explaining the decision
    """
    try:
        # Check if pending seller exists
        pending_seller = await db.get_pending_seller(pending_seller_id)
        if not pending_seller:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Pending seller application not found"
            )

        # Check if already processed
        if pending_seller["status"] != "pending":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Application already {pending_seller['status']}"
            )

        # Update status
        updated_seller = await db.update_pending_seller_status(
            pending_seller_id=pending_seller_id,
            status=approval.status,
            admin_comment=approval.admin_comment
        )
        if not updated_seller:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to update seller status"
            )

        return updated_seller

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error approving seller: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.get("/sellers/application/status", response_model=PendingSellerResponse)
async def get_seller_application_status(
    current_user: Annotated[dict, Depends(get_current_user)]
):
    """
    Get the status of the current user's seller application.
    """
    try:
        pending_seller = await db.get_pending_seller_by_user_id(current_user["user_id"])
        if not pending_seller:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No seller application found"
            )
        return pending_seller
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting seller application status: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )
