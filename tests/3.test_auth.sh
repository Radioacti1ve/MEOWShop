#!/bin/bash
set -e

API_URL="http://localhost:8000/auth"
USERNAME="testuser_$(date +%s)"
EMAIL="test_$(date +%s)@example.com"
PASSWORD="TestPassword123!"

echo "1. Тестирование регистрации..."
REGISTER_RESPONSE=$(curl -s -X POST "$API_URL/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
echo "Ответ регистрации:"
echo "$REGISTER_RESPONSE" | jq .
echo -e "\n----------------------------\n"

echo "2. Тестирование входа..."
LOGIN_RESPONSE=$(curl -s -X POST "$API_URL/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")
echo "Ответ входа:"
echo "$LOGIN_RESPONSE" | jq .

ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r .access_token)
REFRESH_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r .refresh_token)
echo -e "\n----------------------------\n"

echo "3. Тестирование получения информации о пользователе..."
curl -s -X GET "$API_URL/me" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .
echo -e "\n----------------------------\n"

echo "4. Тестирование обновления токена..."
curl -s -X POST "$API_URL/refresh" \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}" | jq .
echo -e "\n----------------------------\n"

echo "5. Тестирование выхода..."
curl -s -X POST "$API_URL/logout" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .
echo -e "\n----------------------------\n"

echo "6. Проверка что токен действительно в черном списке..."
echo "Попытка использовать старый токен:"
curl -s -X GET "$API_URL/me" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .
echo -e "\n----------------------------\n"

echo "Тестирование завершено."
