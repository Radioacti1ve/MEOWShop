USERNAME="user$(date +%s)"
PASSWORD="password123"
EMAIL="${USERNAME}@example.com"

echo "📌 Регистрируем пользователя: $USERNAME"
curl -s -X POST http://localhost:8000/auth/register -H "Content-Type: application/json" -d '{
  "username": "'"$USERNAME"'",
  "email": "'"$EMAIL"'",
  "password": "'"$PASSWORD"'"
}'
echo -e "\n"

echo "📌 Авторизация пользователя: $USERNAME"
RESPONSE=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\", \"password\":\"$PASSWORD\"}")

echo "Ответ сервера на логин: $RESPONSE"
TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
  echo "❌ Ошибка авторизации, токен не получен"
  exit 1
fi

echo -e "\n✅ Получен токен: $TOKEN"

# === Добавляем товары в корзину ===
echo "🛒 Добавляем товар product_id=1, quantity=2"
curl -s -X POST "http://localhost:8000/catalog/cart/add?product_id=1&quantity=2" \
  -H "Authorization: Bearer $TOKEN"
echo -e "\n"

echo "🛒 Добавляем товар product_id=2, quantity=1"
curl -s -X POST "http://localhost:8000/catalog/cart/add?product_id=2&quantity=1" \
  -H "Authorization: Bearer $TOKEN"
echo -e "\n"

# === Совершаем покупку ===
echo "💳 Совершаем покупку товаров из корзины"
curl -s -X POST "http://localhost:8000/catalog/gambling/" \
  -H "Authorization: Bearer $TOKEN" | jq
echo -e "\n"

# === Получаем список заказов текущего пользователя ===
echo "📦 Получаем список заказов пользователя"
curl -s -X GET "http://localhost:8000/users/orders" \
  -H "Authorization: Bearer $TOKEN" | jq
echo -e "\n"
