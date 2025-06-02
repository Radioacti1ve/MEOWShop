#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED_TESTS=0
TOTAL_TESTS=6

# Проверка HTTP статуса
check_status() {
    local response="$1"
    local expected_status="${2:-200}"
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ HTTP статус верный: $http_code${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}✗ Неверный HTTP статус: $http_code (ожидался: $expected_status)${NC}"
        return 1
    fi
}

# Получение тела ответа без HTTP кода
get_response_body() {
    echo "$1" | sed '/HTTP_CODE/d'
}

# Проверка поля в JSON-ответе
check_json_field() {
    local json="$1"
    local field="$2"
    local expected_value="$3"
    local actual_value=$(echo "$json" | jq -r ".$field")
    
    if [ "$actual_value" = "$expected_value" ]; then
        echo -e "${GREEN}✓ Поле $field имеет ожидаемое значение: $actual_value${NC}"
        return 0
    else
        echo -e "${RED}✗ Поле $field имеет неверное значение: $actual_value (ожидалось: $expected_value)${NC}"
        return 1
    fi
}

echo -e "${BLUE}🚀 Запуск тестов регистрации и авторизации администратора...${NC}"

echo -e "\n${BLUE}1️⃣ Регистрация нового администратора...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8000/auth/admins/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_admin",
    "email": "test_admin@example.com",
    "password": "test_password123"
  }')

# Проверяем HTTP статус
check_status "$response" "201"

# Получаем тело ответа и проверяем
RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Получаем pending_admin_id и проверяем его наличие
PENDING_ADMIN_ID=$(echo "$RESPONSE_BODY" | jq -r '.pending_admin_id')
if [[ "$PENDING_ADMIN_ID" == "null" || -z "$PENDING_ADMIN_ID" ]]; then
    echo -e "${RED}✗ Не удалось получить pending_admin_id${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Получен ID заявки администратора: $PENDING_ADMIN_ID${NC}"

echo -e "\n${BLUE}2️⃣ Авторизация существующего администратора...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "hashed_admin_password"
  }')

# Проверяем HTTP статус
check_status "$response"

# Получаем тело ответа
RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Получаем access_token и проверяем его наличие
ACCESS_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
if [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]]; then
    echo -e "${RED}✗ Не удалось получить access_token${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Получен токен доступа${NC}"

echo -e "\n${BLUE}3️⃣ Получение списка заявок на роль администратора...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET http://localhost:8000/auth/admins/pending \
  -H "Authorization: Bearer $ACCESS_TOKEN")

# Проверяем HTTP статус
check_status "$response"

# Получаем тело ответа
RESPONSE_BODY=$(get_response_body "$response")
echo "Список заявок: $RESPONSE_BODY"

# Проверяем что ответ является массивом и содержит нашу заявку
FOUND_ADMIN=$(echo "$RESPONSE_BODY" | jq -r ".[] | select(.pending_admin_id==$PENDING_ADMIN_ID)")
if [[ -z "$FOUND_ADMIN" ]]; then
    echo -e "${RED}✗ Заявка администратора не найдена в списке${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Заявка найдена в списке ожидающих подтверждения${NC}"

echo -e "\n${BLUE}4️⃣ Одобрение заявки администратора...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8000/auth/admins/$PENDING_ADMIN_ID/approve \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "status": "approved",
    "approver_comment": "Одобрено в рамках тестирования"
  }')

# Проверяем HTTP статус
check_status "$response"

# Получаем тело ответа
RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Проверяем статус в ответе
STATUS=$(echo "$RESPONSE_BODY" | jq -r '.status')
if [[ "$STATUS" != "approved" ]]; then
    echo -e "${RED}✗ Неверный статус в ответе: $STATUS (ожидался: approved)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Заявка успешно одобрена${NC}"

echo -e "\n${BLUE}5️⃣ Авторизация нового администратора...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_admin",
    "password": "test_password123"
  }')

# Проверяем HTTP статус
check_status "$response"

# Получаем тело ответа
RESPONSE_BODY=$(get_response_body "$response")
echo "Ответ сервера: $RESPONSE_BODY"

# Получаем токен доступа нового админа
NEW_ADMIN_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
if [[ "$NEW_ADMIN_TOKEN" == "null" || -z "$NEW_ADMIN_TOKEN" ]]; then
    echo -e "${RED}✗ Не удалось получить токен доступа для нового администратора${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Получен токен доступа для нового администратора${NC}"

echo -e "\n${BLUE}6️⃣ Проверка роли нового администратора...${NC}"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET http://localhost:8000/auth/me \
  -H "Authorization: Bearer $NEW_ADMIN_TOKEN")

# Проверяем HTTP статус
check_status "$response"

# Получаем тело ответа
RESPONSE_BODY=$(get_response_body "$response")
echo "Информация о пользователе: $RESPONSE_BODY"

# Проверяем роль в ответе
ROLE=$(echo "$RESPONSE_BODY" | jq -r '.role')
if [[ "$ROLE" != "admin" ]]; then
    echo -e "${RED}✗ Неверная роль пользователя: $ROLE (ожидалась: admin)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Пользователь имеет роль администратора${NC}"

echo -e "\n${BLUE}=== Итоги тестирования ===${NC}"
if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}✅ Все тесты ($PASSED_TESTS из $TOTAL_TESTS) успешно пройдены!${NC}"
    exit 0
else
    echo -e "${RED}❌ Пройдено только $PASSED_TESTS из $TOTAL_TESTS тестов${NC}"
    exit 1
fi