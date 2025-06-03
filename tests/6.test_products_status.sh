#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Счетчики тестов
TOTAL_TESTS=10
PASSED_TESTS=0
declare -a FAILED_TESTS=()

check_status() {
    local response="$1"
    local expected_status="${2:-200}"
    local http_code=$(echo "$response" | grep -oP 'HTTP_CODE:\K[0-9]+' || echo "unknown")
    
    if [[ "$http_code" == "$expected_status" ]]; then
        echo -e "${GREEN}✓ HTTP статус верный: $http_code${NC}"
        return 0
    else
        echo -e "${RED}✗ Неверный HTTP статус: $http_code (ожидался: $expected_status)${NC}"
        return 1
    fi
}

get_response_body() {
    local response="$1"
    echo "$response" | sed '$ d' || echo "$response"
}

log_test_result() {
    local test_name="$1"
    if [[ $2 -eq 0 ]]; then
        ((PASSED_TESTS++))
        echo -e "${GREEN}✓ Тест '$test_name' пройден${NC}"
    else
        FAILED_TESTS+=("$test_name")
        echo -e "${RED}✗ Тест '$test_name' не пройден${NC}"
    fi
}

should_exit() {
    if [[ "${#FAILED_TESTS[@]}" -gt 0 ]]; then
        echo -e "\n${RED}❌ Критическая ошибка в тесте. Останавливаем выполнение.${NC}"
        echo -e "${RED}Проваленные тесты: ${FAILED_TESTS[*]}${NC}"
        exit 1
    fi
}

# База данных
PGHOST="localhost"
PGPORT="5435"
PGUSER="postgres"
PGPASSWORD="123"
PGDATABASE="meowshop"

export PGPASSWORD="$PGPASSWORD"

echo -e "\n🔍 Тестирование управления статусами товаров..."

# 1. Регистрация админа
echo -e "\n1️⃣ Регистрируем нового админа..."
ADMIN_USERNAME="adminUser$(date +%s)"
ADMIN_PASSWORD="password123"
ADMIN_EMAIL="${ADMIN_USERNAME}@example.com"

REGISTER_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"$ADMIN_USERNAME\",\"email\": \"$ADMIN_EMAIL\",\"password\": \"$ADMIN_PASSWORD\"}")

RESPONSE_BODY=$(get_response_body "$REGISTER_RESPONSE")
echo "Ответ на регистрацию:"
echo "$RESPONSE_BODY" | jq '.'

TEST_RESULT=0
if ! check_status "$REGISTER_RESPONSE" "201"; then
    TEST_RESULT=1
fi
log_test_result "register-admin" $TEST_RESULT

# 2. Назначение роли админа
echo -e "\n2️⃣ Делаем пользователя админом..."
ADMIN_USER_ID=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t \
  -c "SELECT user_id FROM \"Users\" WHERE username = '$ADMIN_USERNAME';" | tr -d '[:space:]')

if [[ -z "$ADMIN_USER_ID" ]]; then
    echo -e "${RED}❌ Не удалось получить user_id админа${NC}"
    log_test_result "get-admin-id" 1
else
    echo -e "${GREEN}✅ Админ user_id = $ADMIN_USER_ID${NC}"
    
    UPDATE_RESULT=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t \
        -c "UPDATE \"Users\" SET role = 'admin' WHERE user_id = $ADMIN_USER_ID;")

    if [[ "$UPDATE_RESULT" == "UPDATE 1" ]]; then
        echo -e "${GREEN}✓ Роль админа успешно установлена${NC}"
        log_test_result "set-admin-role" 0
    else
        echo -e "${RED}✗ Не удалось установить роль админа${NC}"
        log_test_result "set-admin-role" 1
    fi
fi

# 3. Авторизация админа
echo -e "\n3️⃣ Авторизуемся как админ..."
LOGIN_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}")

RESPONSE_BODY=$(get_response_body "$LOGIN_RESPONSE")
echo "Ответ на авторизацию:"
echo "$RESPONSE_BODY" | jq '.'

TEST_RESULT=0
if ! check_status "$LOGIN_RESPONSE" "200"; then
    TEST_RESULT=1
fi

TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.access_token')
if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
    echo -e "${RED}✗ Токен не получен${NC}"
    TEST_RESULT=1
fi
log_test_result "admin-login" $TEST_RESULT

# Проверяем, получили ли мы токен для продолжения тестов
if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
    echo -e "${RED}❌ Не удалось получить токен админа. Останавливаем тесты.${NC}"
    should_exit
fi

SELLER_ID=2
PRODUCT_ID=4

# 4. Проверка исходного состояния
echo -e "\n4️⃣ Проверяем исходное состояние товаров..."
INITIAL_STATE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://localhost:8000/catalog/products")

RESPONSE_BODY=$(get_response_body "$INITIAL_STATE")
echo "Исходное состояние товаров:"
echo "$RESPONSE_BODY" | jq '.products[] | select(.seller_id == 2) | {product_id, title, status}'

TEST_RESULT=0
if ! check_status "$INITIAL_STATE" "200"; then
    TEST_RESULT=1
fi
log_test_result "check-initial-state" $TEST_RESULT

# 5. Деактивация всех товаров продавца
echo -e "\n5️⃣ Деактивируем все товары продавца seller_id=$SELLER_ID..."
DISABLE_ALL_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X PUT "http://localhost:8000/admin/products/disable_all/$SELLER_ID" \
  -H "Authorization: Bearer $TOKEN")

RESPONSE_BODY=$(get_response_body "$DISABLE_ALL_RESPONSE")
echo "Ответ на отключение всех товаров:"
echo "$RESPONSE_BODY" | jq '.'

TEST_RESULT=0
if ! check_status "$DISABLE_ALL_RESPONSE" "200"; then
    TEST_RESULT=1
fi

if [[ "$(echo "$RESPONSE_BODY" | jq -r '.detail')" != *"disabled successfully"* ]]; then
    echo -e "${RED}✗ Неверный ответ на деактивацию${NC}"
    TEST_RESULT=1
fi
log_test_result "disable-all-products" $TEST_RESULT

# 6. Проверка деактивации
echo -e "\n6️⃣ Проверяем что все товары продавца недоступны..."
DISABLED_STATE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://localhost:8000/catalog/products")

RESPONSE_BODY=$(get_response_body "$DISABLED_STATE")
echo "Состояние после деактивации:"
echo "$RESPONSE_BODY" | jq '.products[] | select(.seller_id == 2) | {product_id, title, status}'

TEST_RESULT=0
if ! check_status "$DISABLED_STATE" "200"; then
    TEST_RESULT=1
fi

DISABLED_COUNT=$(echo "$RESPONSE_BODY" | jq '[.products[] | select(.seller_id == 2 and .status == "disabled")] | length')
if [[ "$DISABLED_COUNT" -eq 0 ]]; then
    echo -e "${RED}✗ Товары не были деактивированы${NC}"
    TEST_RESULT=1
fi
log_test_result "verify-disabled-state" $TEST_RESULT

# 7. Активация одного товара
echo -e "\n7️⃣ Активируем отдельный товар product_id=$PRODUCT_ID..."
ENABLE_ONE_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X PUT "http://localhost:8000/admin/products/enable/$PRODUCT_ID" \
  -H "Authorization: Bearer $TOKEN")

RESPONSE_BODY=$(get_response_body "$ENABLE_ONE_RESPONSE")
echo "Ответ на включение одного товара:"
echo "$RESPONSE_BODY" | jq '.'

TEST_RESULT=0
if ! check_status "$ENABLE_ONE_RESPONSE" "200"; then
    TEST_RESULT=1
fi

if [[ "$(echo "$RESPONSE_BODY" | jq -r '.detail')" != *"enabled successfully"* ]]; then
    echo -e "${RED}✗ Неверный ответ на активацию${NC}"
    TEST_RESULT=1
fi
log_test_result "enable-single-product" $TEST_RESULT

# 8. Проверка активации одного товара
echo -e "\n8️⃣ Проверяем статус после активации одного товара..."
SINGLE_ENABLED_STATE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://localhost:8000/catalog/products")

RESPONSE_BODY=$(get_response_body "$SINGLE_ENABLED_STATE")
echo "Состояние после активации одного товара:"
echo "$RESPONSE_BODY" | jq '.products[] | select(.product_id == 4) | {product_id, title, status}'

TEST_RESULT=0
if ! check_status "$SINGLE_ENABLED_STATE" "200"; then
    TEST_RESULT=1
fi

PRODUCT_STATUS=$(echo "$RESPONSE_BODY" | jq -r '.products[] | select(.product_id == 4) | .status')
if [[ "$PRODUCT_STATUS" != "available" ]]; then
    echo -e "${RED}✗ Товар не был активирован${NC}"
    TEST_RESULT=1
fi
log_test_result "verify-single-enabled" $TEST_RESULT

# 9. Активация всех товаров
echo -e "\n9️⃣ Активируем все товары продавца seller_id=$SELLER_ID..."
ENABLE_ALL_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X PUT "http://localhost:8000/admin/products/enable_all/$SELLER_ID" \
  -H "Authorization: Bearer $TOKEN")

RESPONSE_BODY=$(get_response_body "$ENABLE_ALL_RESPONSE")
echo "Ответ на включение всех товаров:"
echo "$RESPONSE_BODY" | jq '.'

TEST_RESULT=0
if ! check_status "$ENABLE_ALL_RESPONSE" "200"; then
    TEST_RESULT=1
fi

if [[ "$(echo "$RESPONSE_BODY" | jq -r '.detail')" != *"enabled successfully"* ]]; then
    echo -e "${RED}✗ Неверный ответ на активацию всех товаров${NC}"
    TEST_RESULT=1
fi
log_test_result "enable-all-products" $TEST_RESULT

# 10. Финальная проверка
echo -e "\n🔟 Проверяем финальное состояние товаров..."
FINAL_STATE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://localhost:8000/catalog/products")

RESPONSE_BODY=$(get_response_body "$FINAL_STATE")
echo "Финальное состояние товаров:"
echo "$RESPONSE_BODY" | jq '.products[] | select(.seller_id == 2) | {product_id, title, status}'

TEST_RESULT=0
if ! check_status "$FINAL_STATE" "200"; then
    TEST_RESULT=1
fi

AVAILABLE_COUNT=$(echo "$RESPONSE_BODY" | jq '[.products[] | select(.seller_id == 2 and .status == "available")] | length')
if [[ "$AVAILABLE_COUNT" -eq 0 ]]; then
    echo -e "${RED}✗ Товары не были активированы${NC}"
    TEST_RESULT=1
fi
log_test_result "verify-final-state" $TEST_RESULT

# Выводим итоги
echo -e "\n=== Итоги тестирования ==="
if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ Все тесты ($PASSED_TESTS из $TOTAL_TESTS) успешно пройдены!${NC}"
    exit 0
else
    echo -e "${RED}❌ Провалено ${#FAILED_TESTS[@]} из $TOTAL_TESTS тестов${NC}"
    echo -e "${RED}Проваленные тесты: ${FAILED_TESTS[*]}${NC}"
    exit 1
fi
