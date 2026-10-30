// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <deque>
#include <mutex>
#include <string>
#include <string_view>

#include "core/hle/service/service.h"

namespace Service {

// Prefix of placeholder interfaces for Switch 2 IPC that Eden does not implement.
// ReportUnimplementedFunction answers every unknown command on such an interface with an empty
// success, so boot can go on while the log shows which commands are used.
inline constexpr std::string_view Switch2StubPrefix = "switch2-stub:";

class ISwitch2StubInterface final : public ServiceFramework<ISwitch2StubInterface> {
public:
    explicit ISwitch2StubInterface(Core::System& system_, const char* name)
        : ServiceFramework{system_, name} {}

    // Names must outlive the interface, so they are interned here.
    static const char* InternName(std::string name) {
        static std::mutex mutex;
        static std::deque<std::string> names;
        std::scoped_lock lk{mutex};
        for (const auto& n : names) {
            if (n == name) {
                return n.c_str();
            }
        }
        return names.emplace_back(std::move(name)).c_str();
    }
};

} // namespace Service
