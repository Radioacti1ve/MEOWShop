set -e

API_URL="http://localhost:8000"
USERNAME="testuser_$(date +%s)"
PASSWORD="mypassword"
PRODUCT_ID=1

echo "Регистрация пользователя..."
curl -s -X POST "$API_URL/register" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" \
  | jq .

echo "Авторизация..."
AUTH_RESPONSE=$(curl -s -X POST "$API_URL/login" \
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

  curl -s -X POST "$API_URL/comments" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -d "$payload"
}

echo "Создаём первый комментарий..."
COMMENT1_JSON=$(create_comment "Отличный товар, рекомендую!" 5)
COMMENT1_ID=$(echo "$COMMENT1_JSON" | jq -r '.comment.comment_id')
echo "COMMENT1_ID = $COMMENT1_ID"

echo "Создаём второй комментарий..."
COMMENT2_JSON=$(create_comment "В целом неплохо." 4)
COMMENT2_ID=$(echo "$COMMENT2_JSON" | jq -r '.comment.comment_id')
echo "COMMENT2_ID = $COMMENT2_ID"

echo "Создаём первый ответ (reply) на COMMENT1..."
REPLY1_JSON=$(create_comment "Полностью согласен с вами!" null $COMMENT1_ID)
REPLY1_ID=$(echo "$REPLY1_JSON" | jq -r '.comment.comment_id')
echo "REPLY1_ID = $REPLY1_ID"

echo "Создаём второй ответ (reply) на COMMENT2..."
REPLY2_JSON=$(create_comment "Мне тоже понравилось." null $COMMENT2_ID)
REPLY2_ID=$(echo "$REPLY2_JSON" | jq -r '.comment.comment_id')
echo "REPLY2_ID = $REPLY2_ID"

echo "Редактируем рейтинг первого комментария (ставим 3)..."
curl -s -X PATCH "$API_URL/comments/$COMMENT1_ID" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"rating": 3}' | jq .

echo "Удаляем первый комментарий (soft delete)..."
curl -s -X DELETE "$API_URL/comments/$COMMENT1_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .

echo "Удаляем второй комментарий (ответ)..."
curl -s -X DELETE "$API_URL/comments/$REPLY2_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .

echo "Тестирование завершено."
