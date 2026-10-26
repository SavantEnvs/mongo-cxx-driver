// Fuzzes MongoDB connection-string parsing (mongocxx::uri -> libmongoc's URI parser) and every accessor.
#include <cstddef>
#include <cstdint>
#include <strings.h>
#include <memory>
#include <string>

#include <bsoncxx/json.hpp>
#include <mongocxx/exception/exception.hpp>
#include <mongocxx/instance.hpp>
#include <mongocxx/uri.hpp>

namespace {
std::unique_ptr<mongocxx::instance> g_instance;
}

extern "C" int LLVMFuzzerInitialize(int*, char***) {
    g_instance = std::make_unique<mongocxx::instance>();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(std::uint8_t const* data, std::size_t size) {
    std::string const text{reinterpret_cast<char const*>(data), size};
    // `mongodb+srv://` makes the driver resolve DNS while parsing; that is network behavior, not parser
    // logic, and would make runs depend on the host's resolver, so those inputs are rejected.
    static char const srv[] = "mongodb+srv:";
    if (size >= sizeof(srv) - 1 && strncasecmp(text.c_str(), srv, sizeof(srv) - 1) == 0) return -1;
    std::size_t sink = 0;
    try {
        mongocxx::uri const u{text};
        sink += u.to_string().size() + u.database().size() + u.username().size() + u.password().size();
        sink += u.auth_mechanism().size() + u.auth_source().size() + u.replica_set().size();
        sink += u.hosts().size() + u.tls();
        sink += bsoncxx::to_json(u.options()).size();
        sink += bsoncxx::to_json(u.read_concern().to_document()).size();
        sink += bsoncxx::to_json(u.write_concern().to_document()).size();
        sink += static_cast<std::size_t>(u.read_preference().mode());
        for (auto const& h : u.hosts()) sink += h.name.size() + h.port;
        sink += u.appname().has_value();
        sink += u.compressors().size();
        sink += u.auth_mechanism_properties().has_value();
        sink += u.max_pool_size().has_value() + u.retry_reads().has_value() + u.retry_writes().has_value();
        sink += u.server_selection_timeout_ms().has_value() + u.socket_timeout_ms().has_value();
        sink += u.tls_ca_file().has_value() + u.tls_certificate_key_file().has_value();
        sink += u.zlib_compression_level().has_value() + u.srv_max_hosts().has_value();
    } catch (mongocxx::exception const&) {
        return -1;
    }
    return sink == static_cast<std::size_t>(-1) ? 1 : 0;
}
