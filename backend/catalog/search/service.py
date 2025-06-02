from typing import List, Dict, Any, Optional
from elasticsearch.exceptions import NotFoundError
from elastic.client import get_elasticsearch_client
from elastic.mappings import PRODUCT_INDEX_NAME

class SearchService:
    def __init__(self):
        self.es_client = get_elasticsearch_client()

    async def search_products(
        self,
        query: str,
        category_id: Optional[str] = None,
        page: int = 1,
        page_size: int = 20
    ) -> Dict[str, Any]:
        must_conditions = [{
            "multi_match": {
                "query": query,
                "fields": [
                    "product_name^3",
                    "description^2",
                    "category^2",
                    "seller_name"
                ],
                "fuzziness": "AUTO",
                "operator": "or"  # Changed from 'and' to 'or'
            }
        }]

        if category_id:
            must_conditions.append({"term": {"category.keyword": category_id}})

        body = {
            "query": {"bool": {"must": must_conditions}},
            "from": (page - 1) * page_size,
            "size": page_size,
            "sort": [
                {"_score": "desc"},
                {"avg_rating": {"order": "desc", "missing": "_last"}},
                {"price": "asc"}
            ]
        }

        response = await self.es_client.get_client().search(
            index=PRODUCT_INDEX_NAME,
            body=body
        )

        return {
            "total": response["hits"]["total"]["value"],
            "items": [hit["_source"] for hit in response["hits"]["hits"]]
        }

    async def suggest_products(self, prefix: str, limit: int = 5) -> List[Dict[str, Any]]:
        body = {
            "size": limit,
            "_source": ["product_id", "product_name", "category", "price"],
            "query": {
                "bool": {
                    "should": [
                        {
                            "match_phrase_prefix": {
                                "product_name": {
                                    "query": prefix,
                                    "boost": 10
                                }
                            }
                        },
                        {
                            "match": {
                                "product_name": {
                                    "query": prefix,
                                    "fuzziness": "AUTO",
                                    "boost": 5
                                }
                            }
                        },
                        {
                            "wildcard": {
                                "product_name": {
                                    "value": f"*{prefix}*",
                                    "boost": 2
                                }
                            }
                        },
                        {
                            "match": {
                                "product_name": {
                                    "query": prefix,
                                    "fuzziness": 2,
                                    "prefix_length": 1
                                }
                            }
                        }
                    ],
                    "minimum_should_match": 1,
                    "filter": [
                        {"term": {"status": "available"}},
                        {"range": {"in_stock": {"gt": 0}}}
                    ]
                }
            },
            "sort": [
                {"_score": "desc"},
                {"avg_rating": {"order": "desc", "missing": "_last"}},
                {"price": "asc"}
            ]
        }

        response = await self.es_client.get_client().search(
            index=PRODUCT_INDEX_NAME,
            body=body
        )

        return [{
            "id": hit["_source"]["product_id"],
            "name": hit["_source"]["product_name"],
            "category": hit["_source"]["category"],
            "price": str(hit["_source"]["price"])
        } for hit in response["hits"]["hits"]]

    async def get_similar_products(self, product_id: str, limit: int = 5) -> List[Dict[str, Any]]:
        try:
            product = await self.es_client.get_client().get(
                index=PRODUCT_INDEX_NAME,
                id=product_id
            )
            source = product["_source"]

            body = {
                "query": {
                    "bool": {
                        "should": [
                            {
                                "term": {
                                    "category.keyword": {
                                        "value": source["category"],
                                        "boost": 4.0
                                    }
                                }
                            },
                            {
                                "term": {
                                    "seller_id": {
                                        "value": source["seller_id"],
                                        "boost": 2.0
                                    }
                                }
                            },
                            {
                                "range": {
                                    "price": {
                                        "gte": float(source["price"]) * 0.7,
                                        "lte": float(source["price"]) * 1.3,
                                        "boost": 1.5
                                    }
                                }
                            },
                            {
                                "more_like_this": {
                                    "fields": ["product_name", "description"],
                                    "like": source["description"],
                                    "min_term_freq": 1,
                                    "max_query_terms": 12,
                                    "minimum_should_match": "30%",
                                    "boost": 1.0
                                }
                            }
                        ],
                        "must_not": [
                            {"term": {"product_id": product_id}}
                        ],
                        "filter": [
                            {"term": {"status": "available"}},
                            {"range": {"in_stock": {"gt": 0}}}
                        ],
                        "minimum_should_match": 1
                    }
                },
                "size": limit,
                "_source": True,
                "sort": [
                    {"_score": "desc"},
                    {"avg_rating": {"order": "desc", "missing": "_last"}},
                    {"price": "asc"}
                ]
            }

            response = await self.es_client.get_client().search(
                index=PRODUCT_INDEX_NAME,
                body=body
            )

            return [hit["_source"] for hit in response["hits"]["hits"]]
        except NotFoundError:
            return []
