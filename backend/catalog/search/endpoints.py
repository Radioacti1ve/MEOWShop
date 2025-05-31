from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, Query
from catalog.search.service import SearchService

router = APIRouter(prefix="/catalog", tags=["catalog"])

@router.get("/search")
async def search_products(
    q: str = Query(..., description="Search query"),
    category_id: Optional[str] = Query(None, description="Filter by category ID"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    search_service: SearchService = Depends(lambda: SearchService())
) -> Dict[str, Any]:
    """
    Search for products with pagination and optional category filter.
    Returns matching products ordered by relevance.
    """
    return await search_service.search_products(
        query=q,
        category_id=category_id,
        page=page,
        page_size=page_size
    )

@router.get("/suggest")
async def suggest_products(
    q: str = Query(..., min_length=1, description="Prefix to get suggestions for"),
    limit: int = Query(5, ge=1, le=20, description="Maximum number of suggestions"),
    search_service: SearchService = Depends(lambda: SearchService())
) -> List[Dict[str, str]]:
    """
    Get product name suggestions for autocomplete functionality.
    Returns a list of product IDs and names that match the given prefix.
    """
    return await search_service.suggest_products(prefix=q, limit=limit)

@router.get("/similar/{product_id}")
async def get_similar_products(
    product_id: str,
    limit: int = Query(5, ge=1, le=20, description="Maximum number of similar products"),
    search_service: SearchService = Depends(lambda: SearchService())
) -> List[Dict[str, Any]]:
    """
    Find products similar to the given product ID.
    Returns a list of similar products based on content similarity.
    """
    return await search_service.get_similar_products(product_id=product_id, limit=limit)
