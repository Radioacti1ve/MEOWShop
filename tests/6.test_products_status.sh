#!/bin/bash
set -e

PGHOST="localhost"
PGPORT="5435"
PGUSER="postgres"
PGPASSWORD="123"
PGDATABASE="meowshop"

export PGPASSWORD="$PGPASSWORD"

echo "1️⃣ Регистрируем нового админа..."
ADMIN_USERNAME="adminUser$(date +%s)"
ADMIN_PASSWORD="password123"
ADMIN_EMAIL="${ADMIN_USERNAME}@example.com"

REGISTER_RESPONSE=$(curl -s -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"$ADMIN_USERNAME\",
    \"email\": \"$ADMIN_EMAIL\",
    \"password\": \"$ADMIN_PASSWORD\"
  }")
echo "Ответ на регистрацию: $REGISTER_RESPONSE"

echo "2️⃣ Делаем пользователя админом..."
ADMIN_USER_ID=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t \
  -c "SELECT user_id FROM \"Users\" WHERE username = '$ADMIN_USERNAME';" | tr -d '[:space:]')

if [[ -z "$ADMIN_USER_ID" ]]; then
  echo "❌ Не удалось получить user_id админа"
  exit 1
fi
echo "✅ Админ user_id = $ADMIN_USER_ID"

psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
  -c "UPDATE \"Users\" SET role = 'admin' WHERE user_id = $ADMIN_USER_ID;"

echo "3️⃣ Авторизуемся как админ..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d "{
    \"username\":\"$ADMIN_USERNAME\",
    \"password\":\"$ADMIN_PASSWORD\"
  }")

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
  echo "❌ Ошибка авторизации админа. Токен не получен."
  exit 1
fi
echo "✅ Получен токен админа"

SELLER_ID=2
PRODUCT_ID=4

# Проверяем текущий статус товаров перед изменениями
echo "4️⃣ Проверяем исходное состояние товаров..."
curl -s "http://localhost:8000/catalog/products" | jq '.products[] | select(.seller_id == 2) | {product_id, title, status}'
echo -e "\n----------------------------\n"

echo "5️⃣ Деактивируем все товары продавца seller_id=$SELLER_ID..."
DISABLE_ALL_RESPONSE=$(curl -s -X PUT "http://localhost:8000/admin/products/disable_all/$SELLER_ID" \
  -H "Authorization: Bearer $TOKEN")

echo "Ответ на отключение всех товаров: $DISABLE_ALL_RESPONSE"

# Проверяем что все товары продавца стали недоступны
echo "6️⃣ Проверяем что все товары продавца недоступны..."
curl -s "http://localhost:8000/catalog/products" | jq '.products[] | select(.seller_id == 2) | {product_id, title, status}'
echo -e "\n----------------------------\n"

echo "7️⃣ Активируем отдельный товар product_id=$PRODUCT_ID..."
ENABLE_ONE_RESPONSE=$(curl -s -X PUT "http://localhost:8000/admin/products/enable/$PRODUCT_ID" \
  -H "Authorization: Bearer $TOKEN")

echo "Ответ на включение одного товара: $ENABLE_ONE_RESPONSE"

# Проверяем что конкретный товар стал доступен
echo "8️⃣ Проверяем статус после активации одного товара..."
curl -s "http://localhost:8000/catalog/products" | jq '.products[] | select(.product_id == 4) | {product_id, title, status}'
echo -e "\n----------------------------\n"

echo "9️⃣ Активируем все товары продавца seller_id=$SELLER_ID..."
ENABLE_ALL_RESPONSE=$(curl -s -X PUT "http://localhost:8000/admin/products/enable_all/$SELLER_ID" \
  -H "Authorization: Bearer $TOKEN")

echo "Ответ на включение всех товаров: $ENABLE_ALL_RESPONSE"

# Финальная проверка статусов
echo "🔟 Проверяем финальное состояние товаров..."
curl -s "http://localhost:8000/catalog/products" | jq '.products[] | select(.seller_id == 2) | {product_id, title, status}'
echo -e "\n----------------------------\n"

echo "✨ Тесты управления статусами товаров завершены успешно!"
