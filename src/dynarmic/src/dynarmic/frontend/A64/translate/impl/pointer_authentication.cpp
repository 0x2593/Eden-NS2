// SPDX-FileCopyrightText: Copyright 2026 Eden Emulator Project
// SPDX-License-Identifier: GPL-3.0-or-later

// ARMv8.3 pointer-authenticated branches and loads, implemented as the identity: PAC* never adds a
// code (system.cpp), so signed pointers are just plain pointers.

#include "dynarmic/frontend/A64/translate/impl/impl.h"

namespace Dynarmic::A64 {

bool TranslatorVisitor::PACAUT_reg(bool Z, Imm<3> op, Reg Rn, Reg Rd) {
    (void)op;
    (void)Rd;
    if (Z && Rn != Reg::R31) {
        return UnallocatedEncoding();
    }
    return true;
}

bool TranslatorVisitor::BRA_BLRA(bool Z, bool L, bool M, Reg Rn, Reg Rm) {
    (void)M;
    if (!Z && Rm != Reg::R31) {
        return UnallocatedEncoding();
    }
    const auto target = X(64, Rn);
    if (L) {
        X(64, Reg::R30, ir.Imm64(ir.PC() + 4));
        ir.PushRSB(ir.current_location->AdvancePC(4));
    }
    ir.SetPC(target);
    ir.SetTerm(IR::Term::FastDispatchHint{});
    return false;
}

bool TranslatorVisitor::LDRA(bool M, bool S, Imm<9> imm9, bool W, Reg Rn, Reg Rt) {
    (void)M;
    const s64 offset = concatenate(Imm<1>{S ? 1u : 0u}, imm9).SignExtend<s64>() << 3;
    const IR::U64 base = Rn == Reg::SP ? IR::U64{SP(64)} : IR::U64{X(64, Rn)};
    const IR::U64 address = ir.Add(base, ir.Imm64(static_cast<u64>(offset)));
    const IR::U64 data = Mem(address, 8, IR::AccType::NORMAL);
    if (W) {
        if (Rn == Reg::SP) {
            SP(64, address);
        } else {
            X(64, Rn, address);
        }
    }
    X(64, Rt, data);
    return true;
}

}  // namespace Dynarmic::A64
