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

# === Удаляем один товар ===
echo "🗑️ Удаляем товар product_id=1"
curl -s -X DELETE "http://localhost:8000/catalog/cart/remove?product_id=1" \
  -H "Authorization: Bearer $TOKEN"
echo -e "\n"

# === Проверяем корзину ===
echo "📦 Содержимое корзины:"
curl -s -X GET http://localhost:8000/catalog/cart/ \
  -H "Authorization: Bearer $TOKEN" | jq

# === Увеличиваем количество товара product_id=2 на 2 ===
echo "🔼 Увеличиваем количество товара product_id=2 на 2"
curl -s -X PATCH "http://localhost:8000/catalog/cart/increase?product_id=2&quantity=2" \
  -H "Authorization: Bearer $TOKEN"
echo -e "\n"

# === Уменьшаем количество товара product_id=2 на 1 ===
echo "🔽 Уменьшаем количество товара product_id=2 на 1"
curl -s -X PATCH "http://localhost:8000/catalog/cart/decrease?product_id=2&quantity=1" \
  -H "Authorization: Bearer $TOKEN"
echo -e "\n"

# === Проверяем корзину ===
echo "📦 Содержимое корзины:"
curl -s -X GET http://localhost:8000/catalog/cart/ \
  -H "Authorization: Bearer $TOKEN" | jq

# === Уменьшаем количество товара product_id=2 на 5 (возможно удалится полностью) ===
echo "🔽 Уменьшаем количество товара product_id=2 на 5 (должен удалиться)"
curl -s -X PATCH "http://localhost:8000/catalog/cart/decrease?product_id=2&quantity=5" \
  -H "Authorization: Bearer $TOKEN"
echo -e "\n"

# === Пробуем добавить товар, которого нет в наличии (product_id=10) ===
echo "🚫 Пытаемся добавить товар product_id=10, quantity=1 (нет в наличии)"
curl -s -X POST "http://localhost:8000/catalog/cart/add?product_id=10&quantity=1" \
  -H "Authorization: Bearer $TOKEN"
echo -e "\n"

# === Финальное состояние корзины ===
echo "📦 Финальное содержимое корзины:"
curl -s -X GET http://localhost:8000/catalog/cart/ \
  -H "Authorization: Bearer $TOKEN" | jq
