// Known-answer probe for mayhem/test.sh: parses an Extended JSON document given on argv[1] and prints
// one line per fact (BSON byte length, canonical/relaxed Extended JSON, element count).
#include <cstdio>
#include <iostream>
#include <string>

#include <bsoncxx/document/value.hpp>
#include <bsoncxx/exception/exception.hpp>
#include <bsoncxx/json.hpp>
#include <bsoncxx/types.hpp>
#include <bsoncxx/validate.hpp>

int main(int argc, char** argv) {
    if (argc != 2) {
        std::fprintf(stderr, "usage: kat <extended-json>\n");
        return 2;
    }
    bsoncxx::document::value doc{bsoncxx::document::view{}};
    try {
        doc = bsoncxx::from_json(argv[1]);
    } catch (bsoncxx::exception const& e) {
        std::cout << "error=" << e.what() << "\n";
        return 3;
    }
    auto const view = doc.view();
    std::size_t count = 0;
    for (auto const& el : view) {
        (void)el;
        ++count;
    }
    std::cout << "length=" << view.length() << "\n"
              << "elements=" << count << "\n"
              << "valid=" << (bsoncxx::validate(view.data(), view.length()) ? 1 : 0) << "\n"
              << "canonical=" << bsoncxx::to_json(view, bsoncxx::ExtendedJsonMode::k_canonical) << "\n"
              << "relaxed=" << bsoncxx::to_json(view, bsoncxx::ExtendedJsonMode::k_relaxed) << "\n";
    return 0;
}
