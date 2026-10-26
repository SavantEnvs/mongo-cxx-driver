// Fuzzes bsoncxx's standalone value parsers: Decimal128 and ObjectId strings/bytes, plus the
// builder's handling of fuzzer-chosen keys and strings. The first byte selects the sub-target.
#include <cstddef>
#include <cstdint>
#include <string>

#include <bsoncxx/builder/basic/array.hpp>
#include <bsoncxx/builder/basic/document.hpp>
#include <bsoncxx/builder/basic/kvp.hpp>
#include <bsoncxx/decimal128.hpp>
#include <bsoncxx/exception/exception.hpp>
#include <bsoncxx/json.hpp>
#include <bsoncxx/oid.hpp>
#include <bsoncxx/stdx/string_view.hpp>

extern "C" int LLVMFuzzerTestOneInput(std::uint8_t const* data, std::size_t size) {
    if (size < 1) return -1;
    std::uint8_t const selector = data[0] % 3;
    char const* const payload = reinterpret_cast<char const*>(data + 1);
    std::size_t const n = size - 1;
    // Embedders hand these constructors std::string-backed (NUL-terminated) views; see
    // fuzz_bson_types/known-findings/ for what a bare, unterminated view does to decimal128.
    std::string const text{payload, n};
    bsoncxx::stdx::string_view const sv{text};

    try {
        switch (selector) {
            case 0: {
                bsoncxx::decimal128 const d{sv};
                bsoncxx::decimal128 const again{d.to_string()};
                (void)(again == d);
                break;
            }
            case 1: {
                bsoncxx::oid const o{sv};
                std::string const s = o.to_string();
                bsoncxx::oid const again{s};
                if (!(again == o)) __builtin_trap();
                (void)o.get_time_t();
                break;
            }
            default: {
                using bsoncxx::builder::basic::kvp;
                bsoncxx::builder::basic::document doc;
                bsoncxx::builder::basic::array arr;
                std::size_t const half = n / 2;
                bsoncxx::stdx::string_view const key{payload, half};
                bsoncxx::stdx::string_view const val{payload + half, n - half};
                doc.append(kvp(key, val));
                arr.append(val, key);
                doc.append(kvp("arr", arr.extract()));
                auto const built = doc.extract();
                (void)bsoncxx::to_json(built.view(), bsoncxx::ExtendedJsonMode::k_canonical);
                break;
            }
        }
    } catch (bsoncxx::exception const&) {
        return -1;
    }
    return 0;
}
