export TEST_TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJidWlsZCIsInNjb3BlIjpbImJ1aWxkIiwicHVibGlzaCJdLCJuYW1lIjoiYWRtaW5fZmluYWwiLCJwcmVmaXhlcyI6WyIiXSwicmVwb3MiOlsic3RhYmxlIl0sImV4cCI6MTc5NzE2MzU4NCwidG9rZW5fdHlwZSI6ImFwcCIsImJyYW5jaGVzIjpbInN0YWJsZSJdfQ.OFsCQV-vCrkxSyTRGff4c1s1U5LylHkaEd0WAGTGaj0"

curl -v -X POST http://127.0.0.1:8080/api/v1/build \
  -H "Authorization: Bearer $TEST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"repo": "stable"}'