#include "prx/libc/include/general/VabiMacros.hpp"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" {
int APS5_VABI sceNpCreateRequest(void);
int APS5_VABI sceNpDeleteRequest(int req_id);
int APS5_VABI sceNpCheckNpAvailability(int req_id, const char* user, void* result);
int APS5_VABI sceNpCheckNpReachability(int req_id, int user_id);
int APS5_VABI sceNpGetNpId(int user_id, void* np_id);
int APS5_VABI sceNpGetOnlineId(int user_id, void* online_id);
int APS5_VABI sceNpGetState(int user_id, std::uint32_t* state);
}

namespace {

constexpr int SignedOut = static_cast<int>(0x80550006u);
constexpr int InvalidArgument = static_cast<int>(0x80550003u);
constexpr std::uint32_t StateSignedOut = 1;

void Require(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "NpManager: %s\n", message);
        std::abort();
    }
}

}

int main() {
    const int request = sceNpCreateRequest();
    Require(request > 0, "request creation failed");

    unsigned char result[64];
    std::memset(result, 0xa5, sizeof(result));
    unsigned char untouched[sizeof(result)];
    std::memcpy(untouched, result, sizeof(result));
    Require(sceNpCheckNpAvailability(request, "user", result) == SignedOut, "availability is not signed out");
    Require(std::memcmp(result, untouched, sizeof(result)) == 0, "failed availability check wrote a result");
    Require(sceNpCheckNpReachability(request, 1) == SignedOut, "reachability is not signed out");

    unsigned char npId[64];
    std::memset(npId, 0xa5, sizeof(npId));
    Require(sceNpGetNpId(1, npId) == SignedOut, "NpId is not signed out");
    Require(std::memcmp(npId, untouched, sizeof(npId)) == 0, "failed NpId query wrote an id");
    Require(sceNpGetOnlineId(1, npId) == SignedOut, "online id is not signed out");

    std::uint32_t state = 0;
    Require(sceNpGetState(1, nullptr) == InvalidArgument, "null state accepted");
    Require(sceNpGetState(1, &state) == 0 && state == StateSignedOut, "state is not signed out");

    Require(sceNpDeleteRequest(request) == 0, "request deletion failed");
}
