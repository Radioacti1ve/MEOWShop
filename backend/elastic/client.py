from elasticsearch import AsyncElasticsearch
from functools import lru_cache
from typing import Optional
import os

class ElasticsearchClient:
    def __init__(self):
        self.client: Optional[AsyncElasticsearch] = None

    async def initialize(self):
        """Initialize the Elasticsearch client"""
        if not self.client:
            self.client = AsyncElasticsearch(
                hosts=[os.getenv("ELASTICSEARCH_URL", "http://elasticsearch:9200")],
                retry_on_timeout=True,
                max_retries=5
            )

    async def close(self):
        """Close the Elasticsearch client connection"""
        if self.client:
            await self.client.close()
            self.client = None

    def get_client(self) -> AsyncElasticsearch:
        """Get the Elasticsearch client instance"""
        if not self.client:
            raise RuntimeError("Elasticsearch client not initialized")
        return self.client

@lru_cache()
def get_elasticsearch_client() -> ElasticsearchClient:
    """Singleton factory function for ElasticsearchClient"""
    return ElasticsearchClient()
