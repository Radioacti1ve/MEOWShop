#!/bin/bash

PASSED_TESTS=0
TOTAL_TESTS=6

check_status() {
    local test_name=$1
    local response=$2
    
    echo -n "Testing: $test_name... "
    if [ $? -eq 0 ] && [ ! -z "$response" ] && [[ $response != *"error"* ]] && [[ $response != *"Error"* ]]; then
        echo -e "\033[0;32m[PASSED]\033[0m"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "\033[0;31m[FAILED]\033[0m"
    fi
}

echo "Starting admin registration flow test..."

echo -e "\n1. Registering new admin..."
REGISTER_RESPONSE=$(curl -s -X POST http://localhost:8000/auth/admins/register \
-H "Content-Type: application/json" \
-d '{
    "username": "test_admin",
    "email": "test_admin@example.com",
    "password": "test_password123"
}')
echo "Register response: $REGISTER_RESPONSE"
PENDING_ADMIN_ID=$(echo $REGISTER_RESPONSE | grep -o '"pending_admin_id":[0-9]*' | grep -o '[0-9]*')
echo -n "Pending admin ID: $PENDING_ADMIN_ID "
check_status "Register new admin" "$REGISTER_RESPONSE"

echo -e "\n2. Login as admin..."
LOGIN_RESPONSE=$(curl -s -X POST http://localhost:8000/auth/login \
-H "Content-Type: application/json" \
-d '{
    "username": "admin",
    "password": "hashed_admin_password"
}')
echo "Login response: $LOGIN_RESPONSE"
ACCESS_TOKEN=$(echo $LOGIN_RESPONSE | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
echo -n "Access token: $ACCESS_TOKEN "
check_status "Login as existing admin" "$LOGIN_RESPONSE"

echo -e "\n3. Getting pending admin applications..."
PENDING_RESPONSE=$(curl -s http://localhost:8000/auth/admins/pending \
-H "Authorization: Bearer $ACCESS_TOKEN")
echo -n "Pending applications: $PENDING_RESPONSE "
check_status "Get pending admin applications" "$PENDING_RESPONSE"

echo -e "\n4. Approving admin application..."
APPROVE_RESPONSE=$(curl -s -X POST http://localhost:8000/auth/admins/$PENDING_ADMIN_ID/approve \
-H "Content-Type: application/json" \
-H "Authorization: Bearer $ACCESS_TOKEN" \
-d '{
    "status": "approved",
    "approver_comment": "Approved in test"
}')
echo "Approve response: $APPROVE_RESPONSE"
check_status "Approve admin application" "$APPROVE_RESPONSE"

echo -e "\n5. Login as new admin..."
NEW_ADMIN_LOGIN=$(curl -s -X POST http://localhost:8000/auth/login \
-H "Content-Type: application/json" \
-d '{
    "username": "test_admin",
    "password": "test_password123"
}')
echo "New admin login response: $NEW_ADMIN_LOGIN"
NEW_ADMIN_TOKEN=$(echo $NEW_ADMIN_LOGIN | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
check_status "Login as new admin" "$NEW_ADMIN_LOGIN"

echo -e "\n6. Checking new admin role..."
USER_INFO=$(curl -s http://localhost:8000/auth/me \
-H "Authorization: Bearer $NEW_ADMIN_TOKEN")
echo "New admin info: $USER_INFO"
check_status "Check new admin role" "$USER_INFO"

echo -e "\n=== Test Summary ==="
echo "$PASSED_TESTS out of $TOTAL_TESTS tests passed"
if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "\033[0;32mAll tests passed successfully!\033[0m"
else
    echo -e "\033[0;31m$((TOTAL_TESTS - PASSED_TESTS)) test(s) failed\033[0m"
    exit 1
fi