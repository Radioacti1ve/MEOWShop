#!/bin/bash

# Цветовые коды для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[1;33m'
BLUE='\033[0;34m'

# Директория с тестами
TEST_DIR="$(dirname "$0")"
cd "$TEST_DIR"

# Создаем директорию для логов если её нет
LOGS_DIR="test_logs"
ARCHIVE_DIR="$LOGS_DIR/archive"
mkdir -p "$LOGS_DIR"
mkdir -p "$ARCHIVE_DIR"

# Архивируем старые логи перед очисткой
archive_old_logs() {
    # Если директория с логами пуста, нечего архивировать
    [ -z "$(ls -A $LOGS_DIR 2>/dev/null)" ] && return 0
    
    local date_stamp=$(date "+%Y%m%d_%H%M%S")
    local archive_file="$ARCHIVE_DIR/logs_${date_stamp}.tar.gz"
    
    # Создаем архив только если есть файлы для архивации
    if compgen -G "$LOGS_DIR/*.log" > /dev/null; then
        # Подавляем вывод tar, чтобы не засорять консоль
        tar -czf "$archive_file" -C "$LOGS_DIR" *.log 2>/dev/null || true
    fi
    
    # Удаляем архивы старше 7 дней
    find "$ARCHIVE_DIR" -name "logs_*.tar.gz" -mtime +7 -delete 2>/dev/null || true
}

# Очищаем старые логи
archive_old_logs
rm -f "$LOGS_DIR"/*.log

# Счетчики для статистики
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# Таймаут для каждого теста (в секундах)
TEST_TIMEOUT=300

# Начальное время выполнения всех тестов
TOTAL_START_TIME=$(date +%s)

# Проверка доступности сервера
check_server() {
    local log_file="$LOGS_DIR/server_check.log"
    for i in {1..30}; do
        local response=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://localhost:8000")
        local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
        
        # Записываем детали в лог
        format_log "Попытка подключения к серверу ($i/30). Ответ: $response" "$log_file"
        
        if [ "$http_code" = "200" ]; then
            format_log "Сервер доступен. HTTP код: $http_code" "$log_file"
            echo -e "${GREEN}✓ Сервер доступен${NC}"
            return 0
        fi
        echo -e "${YELLOW}⌛ Подключение к серверу... (попытка $i/30)${NC}\r"
        sleep 1
    done
    
    format_log "Сервер недоступен после 30 секунд ожидания" "$log_file" "ERROR"
    echo -e "${RED}❌ Сервер недоступен${NC}"
    return 1
}

# Функция для форматирования вывода в лог
format_log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local level="${3:-INFO}"
    printf "[%-19s] [%-5s] %s\n" "$timestamp" "$level" "$1" >> "$2"
}

# Функция для отображения прогресса выполнения тестов
show_progress() {
    local current=$1
    local total=$2
    
    # Проверка деления на ноль
    if [ "$total" -eq 0 ]; then
        return
    fi
    
    local percent=$((current * 100 / total))
    local done=$((percent / 2))
    local remaining=$((50 - done))
    
    printf "\r${BLUE}[%-${done}s%${remaining}s] %d%%${NC} (Тест %d из %d)" \
           "$(printf '#%.0s' $(seq 1 $done))" \
           "$(printf ' %.0s' $(seq 1 $remaining))" \
           "$percent" "$current" "$total"
}

# Функция для форматирования ошибок
format_error() {
    local error_msg="$1"
    local log_file="$2"
    format_log "$error_msg" "$log_file" "ERROR"
    echo "----------------------------------------" >> "$log_file"
    echo "$error_msg" | fold -w 80 -s >> "$log_file"
    echo "----------------------------------------" >> "$log_file"
}

# Функция для запуска теста
run_test() {
    local test_file="$1"
    local test_name="$(basename "$test_file")"
    local log_file="$LOGS_DIR/${test_name}.log"
    local start_time=$(date +%s)

    # Записываем начало теста в лог
    format_log "Начало выполнения теста: $test_name" "$log_file"
    
    # Запускаем тест с перенаправлением всего вывода в лог
    timeout $TEST_TIMEOUT bash "$test_file" >> "$log_file" 2>&1
    local result=$?
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Выводим только результат теста в консоль
    if [ $result -eq 0 ]; then
        PASSED=$((PASSED + 1))
        echo -e "${GREEN}✅ $test_name: успешно (${duration}s)${NC}"
    elif [ $result -eq 124 ]; then
        FAILED=$((FAILED + 1))
        echo -e "${RED}⏰ $test_name: превышен таймаут${NC}"
    else
        FAILED=$((FAILED + 1))
        echo -e "${RED}❌ $test_name: ошибка (код $result, ${duration}s)${NC}"
    fi
    
    # Записываем результат в лог
    if [ $result -eq 0 ]; then
        format_log "✅ Тест успешно завершен за ${duration}s" "$log_file"
    elif [ $result -eq 124 ]; then
        format_log "⏰ Тест превысил таймаут ${TEST_TIMEOUT}s" "$log_file" "ERROR"
    else
        format_log "❌ Тест завершился с ошибкой (код $result) за ${duration}s" "$log_file" "ERROR"
    fi
    
    return $result
}

# Главная функция для поиска и запуска тестов
find_and_run_tests() {
    # Находим все тесты и сортируем их
    local tests=($(find . -maxdepth 1 -type f -name '[0-9]*.test_*.sh' | sort))
    TOTAL=${#tests[@]}
    
    format_log "Найдено тестов: $TOTAL" "$LOGS_DIR/summary.log"
    echo -e "${BLUE}🔍 Запуск $TOTAL тестов...${NC}\n"
    
    local current=1
    for test in "${tests[@]}"; do
        show_progress "$current" "$TOTAL"
        run_test "$test"
        current=$((current + 1))
    done
    echo -e "\n" # Две новые строки после прогресс-бара
}

# Функция для вывода итоговой статистики
print_summary() {
    local total_end_time=$(date +%s)
    local total_duration=$((total_end_time - TOTAL_START_TIME))
    local minutes=$((total_duration / 60))
    local seconds=$((total_duration % 60))
    
    # Записываем итоги в лог
    format_log "==== ИТОГОВАЯ СТАТИСТИКА ====" "$LOGS_DIR/summary.log"
    format_log "Общее время выполнения: ${minutes}m ${seconds}s" "$LOGS_DIR/summary.log"
    format_log "Всего тестов: $TOTAL" "$LOGS_DIR/summary.log"
    format_log "Успешно: $PASSED" "$LOGS_DIR/summary.log"
    format_log "Провалено: $FAILED" "$LOGS_DIR/summary.log"
    [ $SKIPPED -gt 0 ] && format_log "Пропущено: $SKIPPED" "$LOGS_DIR/summary.log"
    
    # Выводим краткую статистику в консоль
    echo -e "\n----------------------------------------"
    echo -e "${BLUE}📊 Итоговая статистика:${NC}"
    echo -e "⏱️  Время выполнения: ${minutes}m ${seconds}s"
    echo -e "📋 Тесты: $TOTAL | ${GREEN}✅ Успешно: $PASSED${NC} | ${RED}❌ Провалено: $FAILED${NC}"
    [ $SKIPPED -gt 0 ] && echo -e "${YELLOW}⏭️  Пропущено: $SKIPPED${NC}"
    echo -e "----------------------------------------"
    
    # Добавляем детальный отчет в файл test_summary.log
    {
        echo "=== Детальный отчет тестирования ==="
        echo "Время начала: $(date -d @$TOTAL_START_TIME '+%Y-%m-%d %H:%M:%S')"
        echo "Время завершения: $(date -d @$total_end_time '+%Y-%m-%d %H:%M:%S')"
        echo "Общее время: ${minutes}m ${seconds}s"
        echo ""
        echo "Результаты по тестам:"
        for test_file in $(find . -maxdepth 1 -name "[0-9]*.test_*.sh" | sort); do
            local test_name=$(basename "$test_file")
            local log_file="$LOGS_DIR/${test_name}.log"
            if [ -f "$log_file" ]; then
                if grep -q "✅ Тест успешно завершен" "$log_file"; then
                    echo "✅ $test_name"
                else
                    echo "❌ $test_name"
                    echo "  Ошибки:"
                    grep -B 1 -A 1 "ERROR" "$log_file" | sed 's/^/    /'
                fi
            fi
        done
    } > "$LOGS_DIR/test_summary.log"
}

# Основной блок выполнения
main() {
    if ! check_server; then
        echo -e "${RED}❌ Невозможно запустить тесты - сервер недоступен${NC}"
        exit 1
    fi
    
    find_and_run_tests
    print_summary
    
    # Устанавливаем код возврата
    if [ $FAILED -eq 0 ] && [ $TOTAL -gt 0 ]; then
        echo -e "${GREEN}✅ Все тесты пройдены успешно!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Некоторые тесты завершились с ошибкой${NC}"
        exit 1
    fi
}

main
