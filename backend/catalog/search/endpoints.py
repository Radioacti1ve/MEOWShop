from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, Query, HTTPException
from catalog.search.service import SearchService

router = APIRouter() 

@router.get("/search")
async def search_products(
    q: str = Query(..., description="Search query"),
    category_id: Optional[str] = Query(None, description="Filter by category ID"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    search_service: SearchService = Depends(lambda: SearchService())
) -> Dict[str, Any]:
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
    return await search_service.suggest_products(prefix=q, limit=limit)

@router.get("/similar/{product_id}")
async def get_similar_products(
    product_id: str,
    limit: int = Query(5, ge=1, le=20, description="Maximum number of similar products"),
    search_service: SearchService = Depends(lambda: SearchService())
) -> List[Dict[str, Any]]:
    products = await search_service.get_similar_products(product_id=product_id, limit=limit)
    if products is None:  # Service will return None for non-existent products
        raise HTTPException(status_code=404, detail="Товар не найден")
    return products
