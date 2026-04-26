// SQLCipher 加密 API（sqlite3_key / sqlite3_rekey）必须在 SQLITE_HAS_CODEC 下才暴露
// 二进制 libsqlcipher 已包含符号；client 端定义此宏即可在 sqlite3.h 中看到声明
#define SQLITE_HAS_CODEC 1
#include <sqlcipher/sqlite3.h>
