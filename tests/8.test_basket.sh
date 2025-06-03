#!/bin/bash

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

TOTAL_TESTS=0
FAILED_TESTS=0

# === Добавляем товары в корзину ===
echo "🛒 Добавляем товар product_id=1, quantity=2"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8000/catalog/cart/add?product_id=1&quantity=2" \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "200" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 200, получен $HTTP_CODE"
    TEST_RESULT=1
fi

if ! echo "$BODY" | jq -e '.detail == "Product added to cart"' >/dev/null; then
    echo "❌ Ошибка: Неверное сообщение в ответе"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 1: $TEST_RESULT (0=успех, 1=ошибка)"
echo -e "\n"

echo "🛒 Добавляем товар product_id=2, quantity=1"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8000/catalog/cart/add?product_id=2&quantity=1" \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "200" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 200, получен $HTTP_CODE"
    TEST_RESULT=1
fi

if ! echo "$BODY" | jq -e '.detail == "Product added to cart"' >/dev/null; then
    echo "❌ Ошибка: Неверное сообщение в ответе"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 2: $TEST_RESULT (0=успех, 1=ошибка)"
echo -e "\n"

# === Удаляем один товар ===
echo "🗑️ Удаляем товар product_id=1"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "http://localhost:8000/catalog/cart/remove?product_id=1" \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "200" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 200, получен $HTTP_CODE"
    TEST_RESULT=1
fi

if ! echo "$BODY" | jq -e '.detail == "Product removed from cart"' >/dev/null; then
    echo "❌ Ошибка: Неверное сообщение в ответе"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 3: $TEST_RESULT (0=успех, 1=ошибка)"
echo -e "\n"

# === Проверяем корзину ===
echo "📦 Содержимое корзины:"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X GET http://localhost:8000/catalog/cart/ \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "200" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 200, получен $HTTP_CODE"
    TEST_RESULT=1
fi

# Проверяем что товар 1 отсутствует в корзине
if echo "$BODY" | jq -e '.items[] | select(.product_id == 1)' >/dev/null; then
    echo "❌ Ошибка: Товар product_id=1 всё ещё в корзине"
    TEST_RESULT=1
fi

# Проверяем что товар 2 присутствует в корзине
if ! echo "$BODY" | jq -e '.items[] | select(.product_id == 2)' >/dev/null; then
    echo "❌ Ошибка: Товар product_id=2 отсутствует в корзине"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 4: $TEST_RESULT (0=успех, 1=ошибка)"
echo -e "\n"

# === Увеличиваем количество товара product_id=2 на 2 ===
echo "🔼 Увеличиваем количество товара product_id=2 на 2"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH "http://localhost:8000/catalog/cart/increase?product_id=2&quantity=2" \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "200" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 200, получен $HTTP_CODE"
    TEST_RESULT=1
fi

if ! echo "$BODY" | jq -e '.detail == "Quantity increased by 2"' >/dev/null; then
    echo "❌ Ошибка: Неверное сообщение в ответе"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 5: $TEST_RESULT (0=успех, 1=ошибка)"
echo -e "\n"

# === Уменьшаем количество товара product_id=2 на 1 ===
echo "🔽 Уменьшаем количество товара product_id=2 на 1"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH "http://localhost:8000/catalog/cart/decrease?product_id=2&quantity=1" \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "200" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 200, получен $HTTP_CODE"
    TEST_RESULT=1
fi

if ! echo "$BODY" | jq -e '.detail == "Quantity decreased by 1"' >/dev/null; then
    echo "❌ Ошибка: Неверное сообщение в ответе"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 6: $TEST_RESULT (0=успех, 1=ошибка)"
echo -e "\n"

# === Проверяем корзину ===
echo "📦 Содержимое корзины:"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X GET http://localhost:8000/catalog/cart/ \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "200" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 200, получен $HTTP_CODE"
    TEST_RESULT=1
fi

# Проверяем количество товара 2
if ! echo "$BODY" | jq -e '.items[] | select(.product_id == 2 and .quantity == 2)' >/dev/null; then
    echo "❌ Ошибка: Количество товара product_id=2 должно быть 2"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 7: $TEST_RESULT (0=успех, 1=ошибка)"
echo -e "\n"

# === Уменьшаем количество товара product_id=2 на 5 (возможно удалится полностью) ===
echo "🔽 Уменьшаем количество товара product_id=2 на 5 (должен удалиться)"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X PATCH "http://localhost:8000/catalog/cart/decrease?product_id=2&quantity=5" \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "200" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 200, получен $HTTP_CODE"
    TEST_RESULT=1
fi

if ! echo "$BODY" | jq -e '.detail == "Product removed from cart due to zero quantity"' >/dev/null; then
    echo "❌ Ошибка: Неверное сообщение в ответе"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 8: $TEST_RESULT (0=успех, 1=ошибка)"
echo -e "\n"

# === Пробуем добавить товар, которого нет в наличии (product_id=10) ===
echo "🚫 Пытаемся добавить товар product_id=10, quantity=1 (нет в наличии)"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://localhost:8000/catalog/cart/add?product_id=10&quantity=1" \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "400" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 400, получен $HTTP_CODE"
    TEST_RESULT=1
fi

if ! echo "$BODY" | jq -e '.detail == "Not enough stock"' >/dev/null; then
    echo "❌ Ошибка: Неверное сообщение об ошибке"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 9: $TEST_RESULT (0=успех, 1=ошибка)"
echo -e "\n"

# === Финальное состояние корзины ===
echo "📦 Финальное содержимое корзины:"
TEST_RESULT=0
TOTAL_TESTS=$((TOTAL_TESTS + 1))
RESPONSE=$(curl -s -w "\n%{http_code}" -X GET http://localhost:8000/catalog/cart/ \
  -H "Authorization: Bearer $TOKEN")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ $HTTP_CODE != "200" ]]; then
    echo "❌ Ошибка: Ожидался HTTP 200, получен $HTTP_CODE"
    TEST_RESULT=1
fi

# Проверяем что товар 10 не был добавлен в корзину
if echo "$BODY" | jq -e '.items[] | select(.product_id == 10)' >/dev/null; then
    echo "❌ Ошибка: Товар product_id=10 не должен быть в корзине"
    TEST_RESULT=1
fi

[[ $TEST_RESULT == 1 ]] && FAILED_TESTS=$((FAILED_TESTS + 1))
echo "$BODY" | jq .
echo "Результат теста 10: $TEST_RESULT (0=успех, 1=ошибка)"

# === Итоговая статистика ===
echo -e "\n=== Итоги тестирования ==="
echo "Всего тестов: $TOTAL_TESTS"
echo "Провалено тестов: $FAILED_TESTS"
echo "Успешных тестов: $((TOTAL_TESTS - FAILED_TESTS))"
[[ $FAILED_TESTS -gt 0 ]] && exit 1 || exit 0
