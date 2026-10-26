# decimal128 string parser reads one byte past a non-NUL-terminated string_view

- **Where:** `bson_decimal128_from_string_w_len()` (mongo-c-driver 2.5.7, `src/libbson/src/bson/bson-decimal128.c:537`),
  reached through `bsoncxx::decimal128(stdx::string_view)` (`src/bsoncxx/lib/bsoncxx/v1/decimal128.cpp:51`).
- **Cause:** the digit-reading loop tests `isdigit(*str_read) || *str_read == '.'` *before* its
  `str_read < string + len` bound, so a view whose last character is a digit or `.` makes it dereference
  `string[len]`. A `std::string` hides this (the terminator is a valid read); an exactly-sized buffer does not.
- **Impact:** 1-byte heap over-read (ASan `heap-buffer-overflow`) for any caller that passes a view into a
  buffer that is not NUL-terminated, e.g. a slice of a network read.
- **Reproducer:** `repro-old-harness.bin` = selector byte `0x00` then `.`; it crashed the first version of
  `fuzz_bson_types.cpp`, which handed the parser an exactly-sized view. The shipped harness now passes a
  `std::string`-backed view so the target explores beyond this one site; replay the file against a
  harness that builds `stdx::string_view{data + 1, size - 1}` directly to see the report.
- **One-line fix:** evaluate the `len` bound first in the loop condition (`str_read < string + len && (isdigit(...) ...)`)
  (and likewise before the `*str_read` reads that follow the radix point).
