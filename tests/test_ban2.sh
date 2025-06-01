#!/bin/bash
set -e

PGHOST="localhost"
PGPORT="5435"
PGUSER="postgres"
PGPASSWORD="123"
PGDATABASE="meowshop"

export PGPASSWORD="$PGPASSWORD"

echo "📌 Регистрируем пользователя (админа)..."
ADMIN_USERNAME="adminUser$(date +%s)"
ADMIN_PASSWORD="password123"
ADMIN_EMAIL="${ADMIN_USERNAME}@example.com"

curl -s -X POST http://localhost:8000/register -H "Content-Type: application/json" -d "{
  \"username\": \"$ADMIN_USERNAME\",
  \"email\": \"$ADMIN_EMAIL\",
  \"password\": \"$ADMIN_PASSWORD\"
}"
echo -e "\n"

echo "🔍 Получаем user_id админа из базы..."
ADMIN_USER_ID=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "SELECT user_id FROM \"Users\" WHERE username = '$ADMIN_USERNAME';" | tr -d '[:space:]')

if [[ -z "$ADMIN_USER_ID" ]]; then
  echo "❌ Не удалось получить user_id админа"
  exit 1
fi
echo "Админ user_id = $ADMIN_USER_ID"

echo "⚙️ Обновляем роль пользователя $ADMIN_USERNAME на admin..."
psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "UPDATE \"Users\" SET role = 'admin' WHERE user_id = $ADMIN_USER_ID;"

echo "🔐 Авторизуем админа $ADMIN_USERNAME..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8000/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}")

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
  echo "❌ Ошибка авторизации админа. Токен не получен."
  exit 1
fi

echo "✅ Получен токен админа: $TOKEN"

SELLER_ID=2
PRODUCT_ID=2

echo "⛔ Делаем все товары seller_id=$SELLER_ID недоступными..."
DISABLE_ALL_RESPONSE=$(curl -s -X PUT http://localhost:8000/admin/products/disable_all/$SELLER_ID \
  -H "Authorization: Bearer $TOKEN")

echo "Ответ на disable_all: $DISABLE_ALL_RESPONSE"

echo "⛔ Делаем товар product_id=$PRODUCT_ID недоступным..."
DISABLE_ONE_RESPONSE=$(curl -s -X PUT http://localhost:8000/admin/products/disable/$PRODUCT_ID \
  -H "Authorization: Bearer $TOKEN")

echo "Ответ на disable product: $DISABLE_ONE_RESPONSE"

curl "http://localhost:8000/catalog/products" | jq

echo "✅ Включаем обратно все товары seller_id=$SELLER_ID..."
ENABLE_ALL_RESPONSE=$(curl -s -X PUT http://localhost:8000/admin/products/enable_all/$SELLER_ID \
  -H "Authorization: Bearer $TOKEN")

echo "Ответ на enable_all: $ENABLE_ALL_RESPONSE"

curl "http://localhost:8000/catalog/products" | jq

echo "✔️ Скрипт выполнен успешно."
