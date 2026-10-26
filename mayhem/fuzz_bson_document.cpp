// Fuzzes bsoncxx's BSON validation and full traversal of validated documents.
#include <cstddef>
#include <cstdint>
#include <string>

#include <bsoncxx/array/view.hpp>
#include <bsoncxx/builder/basic/document.hpp>
#include <bsoncxx/builder/basic/kvp.hpp>
#include <bsoncxx/document/value.hpp>
#include <bsoncxx/document/view.hpp>
#include <bsoncxx/exception/exception.hpp>
#include <bsoncxx/json.hpp>
#include <bsoncxx/types.hpp>
#include <bsoncxx/types/bson_value/view.hpp>
#include <bsoncxx/validate.hpp>

namespace {

std::size_t sink = 0;

void walk_document(bsoncxx::document::view const& doc, int depth);

void walk_value(bsoncxx::types::bson_value::view const& v, int depth) {
    using bsoncxx::type;
    switch (v.type()) {
        case type::k_double: sink += static_cast<std::size_t>(v.get_double().value > 0); break;
        case type::k_string: sink += v.get_string().value.size(); break;
        case type::k_document: walk_document(v.get_document().value, depth + 1); break;
        case type::k_array:
            for (auto const& e : v.get_array().value) {
                walk_value(e.get_value(), depth + 1);
            }
            break;
        case type::k_binary: {
            auto const& b = v.get_binary();
            for (std::uint32_t i = 0; i < b.size; ++i) sink += b.bytes[i];
            break;
        }
        case type::k_undefined: break;
        case type::k_oid:
            sink += v.get_oid().value.to_string().size() + static_cast<std::size_t>(v.get_oid().value.get_time_t() & 1);
            break;
        case type::k_bool: sink += v.get_bool().value; break;
        case type::k_date: sink += static_cast<std::size_t>(v.get_date().to_int64() & 1); break;
        case type::k_null: break;
        case type::k_regex: sink += v.get_regex().regex.size() + v.get_regex().options.size(); break;
        case type::k_dbpointer:
            sink += v.get_dbpointer().collection.size() + v.get_dbpointer().value.to_string().size();
            break;
        case type::k_code: sink += v.get_code().code.size(); break;
        case type::k_symbol: sink += v.get_symbol().symbol.size(); break;
        case type::k_codewscope:
            sink += v.get_codewscope().code.size();
            walk_document(v.get_codewscope().scope, depth + 1);
            break;
        case type::k_int32: sink += static_cast<std::size_t>(v.get_int32().value & 1); break;
        case type::k_timestamp: sink += v.get_timestamp().timestamp + v.get_timestamp().increment; break;
        case type::k_int64: sink += static_cast<std::size_t>(v.get_int64().value & 1); break;
        case type::k_decimal128: sink += v.get_decimal128().value.to_string().size(); break;
        case type::k_maxkey: break;
        case type::k_minkey: break;
        default: break;
    }
}

void walk_document(bsoncxx::document::view const& doc, int depth) {
    for (auto const& el : doc) {
        sink += el.key().size();
        walk_value(el.get_value(), depth);
        // Keyed lookup of what we just iterated over.
        if (doc.find(el.key()) == doc.end()) __builtin_trap();
    }
}

}  // namespace

extern "C" int LLVMFuzzerTestOneInput(std::uint8_t const* data, std::size_t size) {
    // Strict validation (UTF-8 checked) and lax validation (UTF-8 unchecked) both run; a document
    // that passes the lax check is traversed, so UTF-8 handling in the printers is exercised too.
    auto const strict = bsoncxx::validate(data, size);

    bsoncxx::validator lax;
    lax.check_utf8(false);
    auto const view = bsoncxx::validate(data, size, lax);
    if (!view) return -1;
    if (strict && strict->length() != view->length()) __builtin_trap();

    walk_document(*view, 0);

    // Documents with invalid UTF-8 (accepted by the lax check) are legitimately refused by the JSON writer.
    try {
        sink += bsoncxx::to_json(*view, bsoncxx::ExtendedJsonMode::k_legacy).size();
        sink += bsoncxx::to_json(*view, bsoncxx::ExtendedJsonMode::k_relaxed).size();
        sink += bsoncxx::to_json(*view, bsoncxx::ExtendedJsonMode::k_canonical).size();
    } catch (bsoncxx::exception const&) {
    }

    bsoncxx::document::value copy{*view};
    if (copy.view() != *view) __builtin_trap();
    return 0;
}
