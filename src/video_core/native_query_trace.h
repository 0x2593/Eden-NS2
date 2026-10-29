// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <vector>
#include "common/common_types.h"

namespace VideoCommon {
namespace NativeQueryDiagnostics {
struct State {
    State() : file{"native-query-trace.csv", std::ios::trunc} {
        file << "event,asid,gpu,cpu,type,value,flags\n";
    }
    std::mutex mutex;
    std::ofstream file;
    size_t records{};
};
inline State& GetState() {
    static State state;
    return state;
}
} // namespace NativeQueryDiagnostics

// Events: 0=request, 1=written, 2=invalidated, 3=unsynchronized,
// 4=channel suspended, 5=channel resumed, 6=buffer readback,
// 7/8=QMD release slots observed, 9=PCAS request,
// 10=DMA destination (value=source, flags=line bytes), 11=inline write.
// Keep this opt-in and bounded.
inline void TraceNativeQuery(u32 event, u64 asid, u64 gpu, u64 cpu, u32 type, u64 value, u32 flags) {
    if (!std::getenv("EDEN_NATIVE_DRAW_DIAGNOSTICS")) return;
    auto& state = NativeQueryDiagnostics::GetState();
    const std::scoped_lock lock{state.mutex};
    if (state.records++ < 1000000 || event == 4 || event == 5) {
        state.file << event << ',' << asid << ',' << std::hex << gpu << ',' << cpu << ','
                   << type << ',' << value << ',' << flags << std::dec << '\n';
    }
    // Inline writes are bulk traffic; everything else is flushed so a hang keeps its tail.
    if (event != 11 && event != 12) state.file.flush();
}

// EDEN_NATIVE_SEM_WATCH=<hex GPU address>: log every release aimed at that 4 KiB page, with the
// issuing engine instance (one per channel) so cross-channel waits can be matched to writers.
inline bool IsWatchedNativeSemaphore(u64 gpu) {
    // Comma-separated list of pages.
    static const std::vector<u64> pages = [] {
        std::vector<u64> result;
        for (const char* cursor = std::getenv("EDEN_NATIVE_SEM_WATCH"); cursor && *cursor;) {
            char* end{};
            result.push_back(std::strtoull(cursor, &end, 16) & ~u64{0xfff});
            cursor = *end == ',' ? end + 1 : nullptr;
        }
        return result;
    }();
    return std::find(pages.begin(), pages.end(), gpu & ~u64{0xfff}) != pages.end();
}
} // namespace VideoCommon

#define TRACE_NATIVE_SEMAPHORE_RELEASE(source, engine, gpu, value)                                  \
    do {                                                                                           \
        if (VideoCommon::IsWatchedNativeSemaphore(gpu)) {                                          \
            LOG_WARNING(HW_GPU, "Native semaphore watch: {} release by engine {}, address={:#x}, value={:#x}", \
                        source, static_cast<const void*>(engine), static_cast<u64>(gpu),        \
                        static_cast<u64>(value));                                                  \
        }                                                                                          \
    } while (false)

namespace VideoCommon {
} // namespace VideoCommon
