TOKEN=$(curl -s -X POST http://localhost:8000/login \
-H "Content-Type: application/json" \
-d '{"username":"testuser", "password":"mypassword"}' | jq -r '.access_token') && \
curl -X GET "http://localhost:8000/catalog/orders?user_id=1" \
-H "Authorization: Bearer $TOKEN" | jq
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   455  100   455    0     0  45862      0 --:--:-- --:--:-- --:--:-- 50555
{
  "orders": [
    {
      "order_id": 5,
      "status": "completed",
      "total_price": 7990,
      "created_at": "2023-05-20T11:25:00",
      "items": [
        {
          "product_name": "Джинсы Levi's 501",
          "quantity": 1,
          "price": 7990
        }
      ]
    },
    {
      "order_id": 1,
      "status": "completed",
      "total_price": 14989,
      "created_at": "2023-03-10T12:30:00",
      "items": [
        {
          "product_name": "Наушники JBL Tune 510BT",
          "quantity": 1,
          "price": 4999
        },
        {
          "product_name": "Футболка мужская Oversize",
          "quantity": 2,
          "price": 2490
        }
      ]
    }
  ]
}
