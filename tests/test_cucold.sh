TOKEN=$(curl -s -X POST http://localhost:8000/login \
-H "Content-Type: application/json" \
-d '{"username":"testuser", "password":"mypassword"}' | jq -r '.access_token') && \
curl -X GET "http://localhost:8000/catalog/orders?user_id=1" \
-H "Authorization: Bearer $TOKEN" | jq

