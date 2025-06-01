#!/bin/bash

# Цветовые коды для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[1;33m'

# Директория с тестами
TEST_DIR="$(dirname "$0")"
cd "$TEST_DIR"

# Счетчики для статистики
TOTAL=0
PASSED=0
FAILED=0

# Функция для запуска теста
run_test() {
    local test_file="$1"
    local test_name="$(basename "$test_file")"
    
    echo -e "\n${YELLOW}=== Запуск теста: $test_name ===${NC}"
    if bash "$test_file"; then
        echo -e "${GREEN}✅ Тест $test_name прошел успешно${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}❌ Тест $test_name завершился с ошибкой${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Находим все тесты с цифрами в начале имени файла и сортируем их
TESTS=$(find . -maxdepth 1 -type f -name '[0-9]*.test_*.sh' | sort)

# Запускаем каждый тест
for test in $TESTS; do
    TOTAL=$((TOTAL + 1))
    run_test "$test"
done

# Выводим итоговую статистику
echo -e "\n${YELLOW}=== Результаты тестирования ===${NC}"
echo -e "Всего тестов: ${TOTAL}"
echo -e "${GREEN}Успешно: ${PASSED}${NC}"
echo -e "${RED}Неудачно: ${FAILED}${NC}"

# Устанавливаем код возврата в зависимости от результатов
if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 Все тесты пройдены успешно!${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Некоторые тесты завершились с ошибкой${NC}"
    exit 1
fi
