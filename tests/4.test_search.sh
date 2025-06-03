#!/bin/bash
set -e

BASE_URL="http://localhost:8000"

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Счетчики тестов
TOTAL_TESTS=13
PASSED_TESTS=0
declare -a FAILED_TESTS

# Функция для проверки HTTP статуса
check_status() {
    local response="$1"
    local expected_status="${2:-200}"
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ HTTP статус верный: $http_code${NC}"
        return 0
    else
        echo -e "${RED}✗ Неверный HTTP статус: $http_code (ожидался: $expected_status)${NC}"
        return 1
    fi
}

# Функция для получения тела ответа
get_response_body() {
    echo "$1" | sed '/HTTP_CODE/d'
}

# Функция для проверки наличия полей в JSON
check_json_structure() {
    local json="$1"
    local field="$2"
    local error_message="$3"
    
    if echo "$json" | jq -e ".$field" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Поле $field присутствует${NC}"
        return 0
    else
        echo -e "${RED}✗ Ошибка: $error_message${NC}"
        return 1
    fi
}

# Функция для проверки количества результатов
check_results_count() {
    local json="$1"
    local min_count="$2"
    local field="${3:-items}"
    
    local count=$(echo "$json" | jq ".$field | length")
    if [ "$count" -ge "$min_count" ]; then
        echo -e "${GREEN}✓ Найдено достаточно результатов: $count${NC}"
        return 0
    else
        echo -e "${RED}✗ Недостаточно результатов: $count (ожидалось минимум $min_count)${NC}"
        return 1
    fi
}

# Добавляем функцию для проверки массива
check_array_response() {
    local json="$1"
    local min_count="$2"
    
    # Проверяем что ответ это массив
    if echo "$json" | jq -e 'if type=="array" then true else false end' > /dev/null; then
        local count=$(echo "$json" | jq '. | length')
        if [ "$count" -ge "$min_count" ]; then
            echo -e "${GREEN}✓ Найдено достаточно результатов: $count${NC}"
            return 0
        else
            echo -e "${RED}✗ Недостаточно результатов: $count (ожидалось минимум $min_count)${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Ответ не является массивом${NC}"
        return 1
    fi
}

# Функция для логирования результата теста
log_test_result() {
    local test_name="$1"
    local result="$2"
    
    if [ "$result" = "pass" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓ Тест пройден: $test_name${NC}"
    else
        FAILED_TESTS+=("$test_name")
        echo -e "${RED}✗ Тест не пройден: $test_name${NC}"
    fi
}

echo -e "${BLUE}🔍 Начинаем тестирование поискового API...${NC}\n"

echo -e "${BLUE}1️⃣ Тестирование базового поиска...${NC}"
echo "Поиск товаров Xiaomi:"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/search" -d "q=xiaomi")

# Проверяем статус и структуру ответа
if check_status "$response"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем структуру ответа
    if check_json_structure "$RESPONSE_BODY" "items" "Отсутствует массив результатов" && \
       check_json_structure "$RESPONSE_BODY" "total" "Отсутствует общее количество" && \
       check_results_count "$RESPONSE_BODY" 1; then
        log_test_result "Базовый поиск" "pass"
    else
        log_test_result "Базовый поиск" "fail"
    fi
else
    log_test_result "Базовый поиск" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}2️⃣ Тестирование поиска с пагинацией...${NC}"
echo "Поиск устройств (должно вернуть смартфон и наушники):"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/search" \
    --data-urlencode "q=смартфон наушники" -d "page=1" -d "page_size=2")

# Проверяем статус и структуру ответа
if check_status "$response"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем структуру и содержимое ответа
    if check_json_structure "$RESPONSE_BODY" "items" "Отсутствует массив результатов" && \
       check_json_structure "$RESPONSE_BODY" "total" "Отсутствует общее количество" && \
       check_results_count "$RESPONSE_BODY" 2; then
        
        # Проверяем, что размер страницы соответствует запрошенному
        items_count=$(echo "$RESPONSE_BODY" | jq '.items | length')
        if [ "$items_count" -eq 2 ]; then
            echo -e "${GREEN}✓ Размер страницы соответствует запрошенному${NC}"
            log_test_result "Поиск с пагинацией" "pass"
        else
            echo -e "${RED}✗ Неверный размер страницы: $items_count (ожидалось: 2)${NC}"
            log_test_result "Поиск с пагинацией" "fail"
        fi
    else
        log_test_result "Поиск с пагинацией" "fail"
    fi
else
    log_test_result "Поиск с пагинацией" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}3️⃣ Тестирование поиска по категории...${NC}"
echo "Поиск по категории 'Бытовая техника':"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/search" \
    --data-urlencode "q=кофемашина пылесос" \
    --data-urlencode "category_id=Бытовая техника")

# Проверяем статус и структуру ответа
if check_status "$response"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем структуру ответа и категорию результатов
    if check_json_structure "$RESPONSE_BODY" "items" "Отсутствует массив результатов" && \
       check_json_structure "$RESPONSE_BODY" "total" "Отсутствует общее количество" && \
       check_results_count "$RESPONSE_BODY" 1; then
        
        # Проверяем, что все результаты из правильной категории
        wrong_category=$(echo "$RESPONSE_BODY" | jq '.items[] | select(.category != "Бытовая техника") | .id')
        if [ -z "$wrong_category" ]; then
            echo -e "${GREEN}✓ Все результаты из правильной категории${NC}"
            log_test_result "Поиск по категории" "pass"
        else
            echo -e "${RED}✗ Найдены товары из неправильной категории${NC}"
            log_test_result "Поиск по категории" "fail"
        fi
    else
        log_test_result "Поиск по категории" "fail"
    fi
else
    log_test_result "Поиск по категории" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}4️⃣ Тестирование автодополнения...${NC}"
echo "Получение подсказок для 'сма' (должен быть 'смартфон'):"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/suggest" \
    --data-urlencode "q=сма" -d "limit=5")

# Проверяем статус и структуру ответа
if check_status "$response"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем наличие подсказок и их релевантность
    if check_array_response "$RESPONSE_BODY" 1; then
        # Проверяем наличие слова "смартфон" в названии первого товара (без учета регистра)
        product_name=$(echo "$RESPONSE_BODY" | jq -r '.[0].name | ascii_downcase | split(" ")[0]')
        if [[ "${product_name,,}" == "смартфон" ]]; then
            echo -e "${GREEN}✓ Найден товар, начинающийся со слова 'смартфон'${NC}"
            log_test_result "Автодополнение" "pass"
        else
            echo -e "${RED}✗ Первое слово не 'смартфон', получено: $product_name${NC}"
            log_test_result "Автодополнение" "fail"
        fi
    else
        log_test_result "Автодополнение" "fail"
    fi
else
    log_test_result "Автодополнение" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}5️⃣ Тестирование похожих товаров...${NC}"
echo "Поиск похожих товаров для Xiaomi Redmi Note 11 (ID=1):"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$BASE_URL/catalog/search/similar/1?limit=5")

# Проверяем статус и структуру ответа
if check_status "$response"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем что результат это непустой массив
    if check_array_response "$RESPONSE_BODY" 1; then
        # Дополнительно проверяем структуру элементов массива
        if echo "$RESPONSE_BODY" | jq -e '.[0] | has("product_id", "product_name", "category")' > /dev/null; then
            echo -e "${GREEN}✓ Структура товаров корректна${NC}"
            log_test_result "Поиск похожих товаров" "pass"
        else
            echo -e "${RED}✗ Неверная структура товаров${NC}"
            log_test_result "Поиск похожих товаров" "fail"
        fi
    else
        log_test_result "Поиск похожих товаров" "fail"
    fi
else
    log_test_result "Поиск похожих товаров" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}6️⃣ Тестирование поиска с несуществующим текстом...${NC}"
echo "Поиск несуществующего товара:"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/search" \
    -d "q=abcdefghijklmnopqrstuvwxyz123456789")

# Проверяем статус и пустой результат
if check_status "$response"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем, что результаты пустые, но структура правильная
    items_count=$(echo "$RESPONSE_BODY" | jq '.items | length')
    total=$(echo "$RESPONSE_BODY" | jq '.total')
    
    if [ "$items_count" -eq 0 ] && [ "$total" -eq 0 ]; then
        echo -e "${GREEN}✓ Пустой результат для несуществующего товара${NC}"
        log_test_result "Поиск несуществующего товара" "pass"
    else
        echo -e "${RED}✗ Неожиданные результаты для несуществующего товара${NC}"
        log_test_result "Поиск несуществующего товара" "fail"
    fi
else
    log_test_result "Поиск несуществующего товара" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}7️⃣ Тестирование автодополнения с коротким запросом...${NC}"
echo "Получение подсказок для 'пы':"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/suggest" \
    --data-urlencode "q=пы" -d "limit=10")

# Проверяем статус и структуру ответа
if check_status "$response"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем что результат это массив (может быть пустым или нет)
    if echo "$RESPONSE_BODY" | jq -e 'if type=="array" then true else false end' > /dev/null; then
        log_test_result "Автодополнение с коротким запросом" "pass"
    else
        echo -e "${RED}✗ Ответ не является массивом${NC}"
        log_test_result "Автодополнение с коротким запросом" "fail"
    fi
else
    log_test_result "Автодополнение с коротким запросом" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}8️⃣ Тестирование поиска с спец. символами...${NC}"
echo "Поиск с специальными символами:"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/search" \
    --data-urlencode "q=!@#$%^&*")

# Проверяем что запрос обработан корректно
if check_status "$response"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем структуру ответа
    if check_json_structure "$RESPONSE_BODY" "items" "Отсутствует массив результатов" && \
       check_json_structure "$RESPONSE_BODY" "total" "Отсутствует общее количество"; then
        log_test_result "Поиск со спецсимволами" "pass"
    else
        log_test_result "Поиск со спецсимволами" "fail"
    fi
else
    log_test_result "Поиск со спецсимволами" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}9️⃣ Тестирование похожих товаров с несуществующим ID...${NC}"
echo "Поиск похожих товаров для несуществующего ID:"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$BASE_URL/catalog/search/similar/999999?limit=5")

# Проверяем что получаем 404 для несуществующего товара
if check_status "$response" "404"; then
    log_test_result "Похожие товары с несуществующим ID" "pass"
else
    log_test_result "Похожие товары с несуществующим ID" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}🔟 Тестирование поиска в описании...${NC}"
echo "Поиск по слову 'мощность':"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/search" \
    --data-urlencode "q=мощность" -d "page=1" -d "page_size=10")

# Проверяем статус и релевантность результатов
if check_status "$response"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем наличие результатов с нужным словом в описании
    if check_json_structure "$RESPONSE_BODY" "items" "Отсутствует массив результатов"; then
        # Проверяем наличие слова, начинающегося с "мощност"
        descriptions=$(echo "$RESPONSE_BODY" | jq -r '.items[].description')
        if echo "$descriptions" | grep -iP 'мощност\w*' > /dev/null; then
            echo -e "${GREEN}✓ Найден товар, содержащий слово о мощности${NC}"
            log_test_result "Поиск в описании" "pass"
        else
            echo -e "${RED}✗ Не найден товар со словом о мощности${NC}"
            log_test_result "Поиск в описании" "fail"
        fi
    else
        log_test_result "Поиск в описании" "fail"
    fi
else
    log_test_result "Поиск в описании" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

# Обновляем проверки ошибок валидации для использования кода 422

echo -e "${BLUE}1️⃣1️⃣ Тестирование некорректных параметров пагинации...${NC}"
echo "Попытка использовать отрицательную страницу:"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/search" \
    --data-urlencode "q=смартфон" -d "page=-1")

# Проверяем обработку некорректной пагинации
if check_status "$response" "422"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем сообщение об ошибке в формате FastAPI
    if echo "$RESPONSE_BODY" | jq -e '.detail[] | select(.loc[1] == "page")' > /dev/null; then
        echo -e "${GREEN}✓ Найдена ошибка валидации для параметра page${NC}"
        log_test_result "Некорректная пагинация" "pass"
    else
        echo -e "${RED}✗ Не найдена ошибка валидации для параметра page${NC}"
        log_test_result "Некорректная пагинация" "fail"
    fi
else
    log_test_result "Некорректная пагинация" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}1️⃣2️⃣ Тестирование слишком большого размера страницы...${NC}"
echo "Попытка запросить слишком много результатов:"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET -G "$BASE_URL/catalog/search/search" \
    --data-urlencode "q=смартфон" -d "page_size=1000")

# Проверяем обработку слишком большого размера страницы
if check_status "$response" "422"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем сообщение об ошибке в формате FastAPI
    if echo "$RESPONSE_BODY" | jq -e '.detail[] | select(.loc[1] == "page_size")' > /dev/null; then
        echo -e "${GREEN}✓ Найдена ошибка валидации для параметра page_size${NC}"
        log_test_result "Большой размер страницы" "pass"
    else
        echo -e "${RED}✗ Не найдена ошибка валидации для параметра page_size${NC}"
        log_test_result "Большой размер страницы" "fail"
    fi
else
    log_test_result "Большой размер страницы" "fail"
fi
echo -e "\n${BLUE}----------------------------${NC}\n"

echo -e "${BLUE}1️⃣3️⃣ Тестирование поиска без параметра q...${NC}"
echo "Попытка поиска без поискового запроса:"
response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X GET "$BASE_URL/catalog/search/search")

# Проверяем обработку отсутствующего параметра поиска
if check_status "$response" "422"; then
    RESPONSE_BODY=$(get_response_body "$response")
    echo "Ответ сервера:"
    echo "$RESPONSE_BODY" | jq '.'
    
    # Проверяем сообщение об ошибке в формате FastAPI
    if echo "$RESPONSE_BODY" | jq -e '.detail[] | select(.loc[1] == "q")' > /dev/null; then
        echo -e "${GREEN}✓ Найдена ошибка валидации для параметра q${NC}"
        log_test_result "Отсутствующий параметр поиска" "pass"
    else
        echo -e "${RED}✗ Не найдена ошибка валидации для параметра q${NC}"
        log_test_result "Отсутствующий параметр поиска" "fail"
    fi
else
    log_test_result "Отсутствующий параметр поиска" "fail"
fi

# Итоговая статистика
echo -e "\n${BLUE}=== Итоги тестирования ===${NC}"
if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}✅ Все тесты ($PASSED_TESTS из $TOTAL_TESTS) успешно пройдены!${NC}"
    exit 0
else
    echo -e "${RED}❌ Пройдено только $PASSED_TESTS из $TOTAL_TESTS тестов${NC}"
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo -e "\n${RED}Непройденные тесты:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "${RED}  - $test${NC}"
        done
    fi
    exit 1
fi
