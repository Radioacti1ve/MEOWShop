#!/bin/bash
set -e

API_URL="http://localhost:8000"
USERNAME="testuser_$(date +%s)"
PASSWORD="mypassword"
PRODUCT_ID=1

# Initialize test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to track test results
track_test() {
    local description="$1"
    local result="$2"  # "pass" or "fail"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if [ "$result" = "pass" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "✓ $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "❌ $description"
    fi
}

# Helper function to make requests and validate responses
make_request() {
    local method="$1"
    local endpoint="$2"
    local expected_code="$3"
    local description="$4"
    local data="$5"
    local headers=(-H "Content-Type: application/json")
    
    if [ -n "$ACCESS_TOKEN" ]; then
        headers+=(-H "Authorization: Bearer $ACCESS_TOKEN")
    fi
    
    # Make request and capture both status code and body
    local temp_file=$(mktemp)
    local status_code=$(curl -s -w "%{http_code}" -X "$method" "$API_URL$endpoint" \
        "${headers[@]}" ${data:+-d "$data"} -o "$temp_file")
    local response=$(cat "$temp_file")
    rm "$temp_file"
    
    if [ "${DEBUG:-0}" = "1" ]; then
        echo ">> Request: $method $endpoint ${data:+with data: $data}"
        echo ">> Response status: $status_code"
        echo ">> Response body: $response"
    fi
    
    if [ "$status_code" != "$expected_code" ]; then
        echo "❌ $description failed - Expected status code $expected_code but got $status_code"
        echo "Response: $response"
        exit 1
    fi
    
    if ! echo "$response" | jq . >/dev/null 2>&1; then
        echo "❌ $description failed - Invalid JSON response"
        echo "Response: $response"
        exit 1
    fi
    
    # Return only the JSON response
    echo "$response"
}

echo "Регистрация пользователя..."
register_response=$(make_request "POST" "/auth/register" "201" "User registration" \
    "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"email\":\"${USERNAME}@example.com\"}")
track_test "Регистрация пользователя" "pass"

sleep 1

echo "Авторизация..."
auth_response=$(make_request "POST" "/auth/login" "200" "User login" \
    "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}")

ACCESS_TOKEN=$(echo "$auth_response" | jq -r .access_token)
if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo "❌ Failed to get access token"
    echo "Auth response: $auth_response"
    exit 1
fi
track_test "Авторизация и получение токена" "pass"

# Helper function to create comments
create_comment() {
    local text="$1"
    local rating="$2"
    local reply_to="$3"
    local payload="{\"product_id\":$PRODUCT_ID,\"text\":\"$text\""
    
    if [ -z "$reply_to" ]; then
        payload="$payload,\"rating\":$rating,\"reply_to_comment_id\":null"
    else
        payload="$payload,\"rating\":null,\"reply_to_comment_id\":$reply_to"
    fi
    payload="$payload}"
    
    local desc="Creating ${reply_to:+reply }comment${reply_to:+ to $reply_to}"
    make_request "POST" "/catalog/comments" "201" "$desc" "$payload"
}

echo "Создание корневого комментария..."
comment1_response=$(create_comment "Отличный товар, рекомендую!" 5)
COMMENT1_ID=$(echo "$comment1_response" | jq -r '.comment.comment_id')
if [ -z "$COMMENT1_ID" ] || [ "$COMMENT1_ID" = "null" ]; then
    echo "❌ Ошибка создания корневого комментария"
    echo "$comment1_response"
    exit 1
fi
track_test "Создание корневого комментария" "pass"
echo "ID корневого комментария: $COMMENT1_ID"

echo "Создание первого ответа..."
reply1_response=$(create_comment "Полностью согласен с вами!" null "$COMMENT1_ID")
REPLY1_ID=$(echo "$reply1_response" | jq -r '.comment.comment_id')
if [ -z "$REPLY1_ID" ] || [ "$REPLY1_ID" = "null" ]; then
    echo "❌ Ошибка создания первого ответа"
    echo "$reply1_response"
    exit 1
fi
track_test "Создание первого ответа на комментарий" "pass"
echo "ID первого ответа: $REPLY1_ID"

echo "Создание второго ответа..."
reply2_response=$(create_comment "Мне тоже понравилось." null "$COMMENT1_ID")
REPLY2_ID=$(echo "$reply2_response" | jq -r '.comment.comment_id')
if [ -z "$REPLY2_ID" ] || [ "$REPLY2_ID" = "null" ]; then
    echo "❌ Ошибка создания второго ответа"
    echo "$reply2_response"
    exit 1
fi
track_test "Создание второго ответа на комментарий" "pass"
echo "ID второго ответа: $REPLY2_ID"

echo "Обновление корневого комментария..."
update_response=$(make_request "PUT" "/catalog/comments/$COMMENT1_ID" "200" "Updating comment" \
    '{"text": "Отличный товар, но есть небольшие недочеты"}')
track_test "Обновление текста комментария" "pass"

echo "Удаление комментариев..."
make_request "DELETE" "/catalog/comments/$COMMENT1_ID" "200" "Deleting first comment"
make_request "DELETE" "/catalog/comments/$REPLY2_ID" "200" "Deleting second comment"
track_test "Удаление комментариев" "pass"

# Print test summary
echo "----------------------------------------"
echo "Результаты тестирования:"
echo "Всего тестов:     $TESTS_TOTAL"
echo "Успешных тестов:  $TESTS_PASSED"
echo "Неудачных тестов: $TESTS_FAILED"
echo "----------------------------------------"

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✓ Тестирование завершено успешно"
    exit 0
else
    echo "❌ Тестирование завершено с ошибками"
    exit 1
fi
