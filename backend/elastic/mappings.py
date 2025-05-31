from typing import Dict, Any

PRODUCT_INDEX_NAME = "products"

PRODUCT_MAPPINGS: Dict[str, Any] = {
    "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "analysis": {
            "filter": {
                "russian_stop": {
                    "type": "stop",
                    "stopwords": "_russian_"
                },
                "russian_stemmer": {
                    "type": "stemmer",
                    "language": "russian"
                },
                "word_delimiter": {
                    "type": "word_delimiter_graph",
                    "preserve_original": True
                }
            },
            "analyzer": {
                "russian_custom": {
                    "type": "custom",
                    "tokenizer": "standard",
                    "filter": [
                        "lowercase",
                        "word_delimiter",
                        "russian_stop",
                        "russian_stemmer"
                    ]
                },
                "ngram_analyzer": {
                    "type": "custom",
                    "tokenizer": "ngram_tokenizer",
                    "filter": [
                        "lowercase",
                        "russian_stop",
                        "russian_stemmer"
                    ]
                }
            },
            "tokenizer": {
                "ngram_tokenizer": {
                    "type": "ngram",
                    "min_gram": 2,
                    "max_gram": 3,
                    "token_chars": [
                        "letter",
                        "digit"
                    ]
                }
            }
        }
    },
    "mappings": {
        "properties": {
            "product_id": {"type": "keyword"},
            "seller_id": {"type": "keyword"},
            "product_name": {
                "type": "text",
                "analyzer": "russian_custom",
                "fields": {
                    "keyword": {"type": "keyword"},
                    "ngram": {
                        "type": "text",
                        "analyzer": "ngram_analyzer",
                        "search_analyzer": "russian_custom"
                    },
                    "completion": {
                        "type": "completion",
                        "analyzer": "russian_custom"
                    }
                }
            },
            "description": {
                "type": "text",
                "analyzer": "russian_custom"
            },
            "price": {"type": "float"},
            "category": {
                "type": "text",
                "analyzer": "russian_custom",
                "fields": {
                    "keyword": {"type": "keyword"}
                }
            },
            "in_stock": {"type": "integer"},
            "status": {"type": "keyword"},
            "seller_name": {
                "type": "text",
                "analyzer": "russian_custom",
                "fields": {
                    "keyword": {"type": "keyword"}
                }
            },
            "avg_rating": {"type": "float"}
        }
    }
}

async def create_product_index(client):
    """Create the product index if it doesn't exist"""
    if await client.indices.exists(index=PRODUCT_INDEX_NAME):
        await client.indices.delete(index=PRODUCT_INDEX_NAME)
    await client.indices.create(
        index=PRODUCT_INDEX_NAME,
        mappings=PRODUCT_MAPPINGS["mappings"],
        settings=PRODUCT_MAPPINGS["settings"]
    )
