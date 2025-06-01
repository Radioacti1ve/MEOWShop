set -e

API_URL="http://localhost:8000"
USERNAME="testuser_$(date +%s)"
PASSWORD="mypassword"
PRODUCT_ID=1

echo "Регистрация пользователя..."
curl -s -X POST "$API_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"email\":\"${USERNAME}@example.com\"}" \
  | jq .

echo "Авторизация..."
AUTH_RESPONSE=$(curl -s -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | jq -r .access_token)
echo "Токен получен: $ACCESS_TOKEN"

function create_comment {
  local text="$1"
  local rating="$2"
  local reply_to="$3"
  local payload
  if [ -z "$reply_to" ]; then
    payload="{\"product_id\":$PRODUCT_ID,\"text\":\"$text\",\"rating\":$rating,\"reply_to_comment_id\":null}"
  else
    payload="{\"product_id\":$PRODUCT_ID,\"text\":\"$text\",\"rating\":null,\"reply_to_comment_id\":$reply_to}"
  fi

  curl -s -X POST "$API_URL/catalog/comments" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$payload"
}

echo "Создаём первый комментарий..."
COMMENT1_JSON=$(create_comment "Отличный товар, рекомендую!" 5)
COMMENT1_ID=$(echo "$COMMENT1_JSON" | jq -r '.comment.comment_id')
echo "COMMENT1_ID = $COMMENT1_ID"
if [ -z "$COMMENT1_ID" ] || [ "$COMMENT1_ID" = "null" ]; then
    echo "❌ Ошибка создания первого комментария"
    echo "$COMMENT1_JSON"
    exit 1
fi

echo "Создаём первый ответ (reply) на COMMENT1..."
REPLY1_JSON=$(create_comment "Полностью согласен с вами!" null $COMMENT1_ID)
REPLY1_ID=$(echo "$REPLY1_JSON" | jq -r '.comment.comment_id')
echo "REPLY1_ID = $REPLY1_ID"
if [ -z "$REPLY1_ID" ] || [ "$REPLY1_ID" = "null" ]; then
    echo "❌ Ошибка создания первого ответа"
    echo "$REPLY1_JSON"
    exit 1
fi

echo "Создаём второй ответ (reply) на COMMENT1..."
REPLY2_JSON=$(create_comment "Мне тоже понравилось." null $COMMENT1_ID)
REPLY2_ID=$(echo "$REPLY2_JSON" | jq -r '.comment.comment_id')
echo "REPLY2_ID = $REPLY2_ID"
if [ -z "$REPLY2_ID" ] || [ "$REPLY2_ID" = "null" ]; then
    echo "❌ Ошибка создания второго ответа"
    echo "$REPLY2_JSON"
    exit 1
fi

echo "Редактируем текст первого комментария..."
curl -s -X PUT "$API_URL/catalog/comments/$COMMENT1_ID" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"text": "Отличный товар, но есть небольшие недочеты"}' | jq .

echo "Удаляем первый комментарий (soft delete)..."
curl -s -X DELETE "$API_URL/catalog/comments/$COMMENT1_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .

echo "Удаляем второй комментарий (ответ)..."
curl -s -X DELETE "$API_URL/catalog/comments/$REPLY2_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .

echo "Тестирование завершено."
