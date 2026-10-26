// Fuzzes bsoncxx's Extended JSON parser and serializers.
#include <cstddef>
#include <cstdint>
#include <string>

#include <bsoncxx/document/value.hpp>
#include <bsoncxx/exception/exception.hpp>
#include <bsoncxx/json.hpp>
#include <bsoncxx/stdx/string_view.hpp>
#include <bsoncxx/validate.hpp>

extern "C" int LLVMFuzzerTestOneInput(std::uint8_t const* data, std::size_t size) {
    bsoncxx::stdx::string_view const json{reinterpret_cast<char const*>(data), size};

    try {
        auto const doc = bsoncxx::from_json(json);
        auto const view = doc.view();

        // A document the parser produced must be structurally valid BSON.
        bsoncxx::validator lax;
        lax.check_utf8(false);
        if (!bsoncxx::validate(view.data(), view.length(), lax)) __builtin_trap();

        // Serializing and re-parsing the canonical form exercises both directions in each mode.
        for (auto mode : {bsoncxx::ExtendedJsonMode::k_legacy,
                          bsoncxx::ExtendedJsonMode::k_relaxed,
                          bsoncxx::ExtendedJsonMode::k_canonical}) {
            std::string const out = bsoncxx::to_json(view, mode);
            try {
                auto const again = bsoncxx::from_json(out);
                (void)again.view().length();
            } catch (bsoncxx::exception const&) {
            }
        }
    } catch (bsoncxx::exception const&) {
        return -1;
    }
    return 0;
}
