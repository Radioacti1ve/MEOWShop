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

NEW_USERNAME="${USERNAME}_updated"
NEW_EMAIL="${NEW_USERNAME}@example.com"

echo -e "\n📌 Обновляем профиль пользователя (username и email)"
curl -s -X PUT http://localhost:8000/users/profile/update \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "new_username": "'"$NEW_USERNAME"'",
    "new_email": "'"$NEW_EMAIL"'"
  }'
echo -e "\n"
