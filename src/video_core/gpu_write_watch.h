// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <atomic>
#include <cstdlib>
#include <mutex>
#include <utility>
#include <vector>
#include "common/common_types.h"
#include "common/logging.h"

namespace VideoCommon {

// EDEN_GPU_WRITE_WATCH=<start>-<end> (hex GPU addresses): reports GPU-side writers whose
// destination overlaps the range. Diagnostic only; rate-limited.
inline bool GpuWriteWatchOverlaps(u64 address, u64 size) {
    static const std::pair<u64, u64> range = [] {
        const char* value = std::getenv("EDEN_GPU_WRITE_WATCH");
        if (!value) return std::pair<u64, u64>{0, 0};
        char* end{};
        const u64 start = std::strtoull(value, &end, 16);
        const u64 stop = end && *end == '-' ? std::strtoull(end + 1, nullptr, 16) : start;
        return std::pair<u64, u64>{start, stop};
    }();
    return range.second > range.first && address < range.second && address + size > range.first;
}

// Which engine the storage buffer being resolved belongs to (diagnostic tag).
inline const char*& GpuWriteWatchKind() {
    static thread_local const char* kind = "unknown";
    return kind;
}

// Device ranges registered at runtime (e.g. vertex streams found empty); CPU writes into them are
// reported. Bounded and lock-protected; diagnostic only.
struct WatchedDeviceRanges {
    std::mutex mutex;
    std::vector<std::pair<u64, u64>> ranges;
};
inline WatchedDeviceRanges& GetWatchedDeviceRanges() {
    static WatchedDeviceRanges ranges;
    return ranges;
}
inline void WatchDeviceRange(u64 start, u64 size) {
    auto& watched = GetWatchedDeviceRanges();
    std::scoped_lock lock{watched.mutex};
    if (watched.ranges.size() >= 256) return;
    for (const auto& [begin, end] : watched.ranges)
        if (start >= begin && start + size <= end) return;
    watched.ranges.emplace_back(start, start + size);
}
inline bool IsWatchedDeviceRange(u64 start, u64 size) {
    auto& watched = GetWatchedDeviceRanges();
    std::scoped_lock lock{watched.mutex};
    for (const auto& [begin, end] : watched.ranges)
        if (start < end && start + size > begin) return true;
    return false;
}

inline bool GpuWriteWatchBudget() {
    static std::atomic<u32> reports{};
    return reports++ < 400;
}

} // namespace VideoCommon

// `format` continues the message after "address=..., size=..."; the remaining arguments fill it.
#define GPU_WRITE_WATCH(what, address, size, format, ...)                                          \
    do {                                                                                           \
        if (VideoCommon::GpuWriteWatchOverlaps(address, size) && VideoCommon::GpuWriteWatchBudget()) \
            LOG_WARNING(HW_GPU, "GPU write watch: " what ", address={:#x}, size={:#x}" format,     \
                        static_cast<u64>(address), static_cast<u64>(size) __VA_OPT__(,) __VA_ARGS__); \
    } while (false)
