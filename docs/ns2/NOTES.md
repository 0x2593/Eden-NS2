# Eden + NS2 patch — work log

Goal: Eden (yuzu fork) with the Switch 2 support patch `NS2_old.patch`, built on Windows, running
Donkey Kong Bananza (title 040074A01BF12000, update v7.0.0 = `458752`) to its main menu.

Tool output (screenshots, logs, dumps) goes to `tools/ns2/out/`, which is not committed.

## Environment and decisions

- Checkout: this folder, extracted from the master archive (no .git originally).
- Local git repo created with a baseline commit `1ed3ddd` = pristine upstream master, so every change
  is diffable/revertible.
- Toolchain: no MSVC/Qt on this PC, MSYS2 was installed but empty. Chose MSYS2 MINGW64 (GCC 16.2,
  CMake 4.4, Ninja, Qt 6.12 from pacman) because it is the fastest supported route.
  - pacman mirrors rate-limited (HTTP 429); retried in a loop. enet/libusb/VMA are not packaged:
    forced CPM bundled copies (`-Denet_FORCE_BUNDLED=ON -Dlibusb_FORCE_BUNDLED=ON
    -DVulkanMemoryAllocator_FORCE_BUNDLED=ON`). Added ffmpeg + autotools packages.
  - libusb's bundled autotools build fails under MSYS2 (aclocal path) -> `-DENABLE_LIBUSB=OFF`
    (only GameCube-adapter passthrough is lost).
- Configure: `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
  -DYUZU_TESTS=OFF -DENABLE_WERROR=OFF -DYUZU_ROOM=OFF -DYUZU_CMD=OFF ... -DENABLE_LIBUSB=OFF`.
- Build: `ninja yuzu` inside `build/` from an MSYS2 MINGW64 shell -> `build/bin/eden.exe`.
- Runtime deps: copied MinGW DLLs next to eden.exe (incl. Qt's own deps: icu, pcre2-16, md4c,
  double-conversion, b2) and wrote `build/bin/qt.conf` (`Plugins = plugins`) — without it Qt
  reported "no Qt platform plugin".
- Game launch: `build/bin/eden.exe -g "<DK>\updates\458752\exefs\main"` (update romfs is the full
  merged romfs; the base game v1.0 fails at its first AM call with proxy flags=0x2, not pursued).

## Eden config (%APPDATA%\eden\config\qt-config.ini)

User-requested: `memory_layout_mode=4` (12 GB), `backend=1` (Vulkan). `use_multi_core=true` is
required since the fourth round (single-core livelocks at the menu, see item 26).
Debug settings added: `use_auto_stub=true`, `rng_seed_enabled=true`/`rng_seed=0`
(fixed load addresses: rtld 0x80000000, main 0x80020000, sdk 0x82830000), `log_filter="*:Info"`,
`use_gdbstub=false` (was toggled on for GDB sessions).

## Patch application

`git apply --reject`: 152/154 files clean; 2 hunks hand-merged (context drift only):
- `src/core/hle/service/service.cpp`: added `<limits>` and `k_thread.h` includes.
- `src/video_core/renderer_vulkan/vk_pipeline_cache.cpp`: `native_turing` early-return in
  `BuiltPipeline`.

## Fixes made on top of the patch (chronological)

Each was found from the Eden log, GDB (Eden's gdbstub + gdb-multiarch) and disassembly of the
game's `sdk` NSO (capstone; symbols from its dynsym/PLT).

1. VI2 cmd 31: returns an event handle (game expected a handle; got 2001-0114 InvalidHandle).
2. Unknown VI2/syncpoint commands honor `use_auto_stub` instead of always NotImplemented.
3. `native_image_layout.h`: image size scaled by preference words 6/7 (layer/mip count).
4. IGpuWorker cmd 214: unbacked (sparse) VA reservation; signals notification, returns kind.
5. GameShare `GetRequiredMemorySize`: accept mode 0 (was HIPC NotSupported -> abort 2011-0001).
6. Subcontexts: NvRm only allowed 1 subcontext per TSG, so the game's 2nd subcontext queue failed
   `nvnQueueInitialize` (ignored by the game -> null command buffer -> crash). Root cause traced
   with GDB to `count = (flags bit22 && TSG ioctl level > 0xa) ? characteristics[0xb4] : 1`.
   Fixed in `native_gpu_characteristics.h` (flag bit 22, VEIDs=64 at 0xb4, TSG level 0xb) and
   `nvhost_tsg_gpu.cpp` (TSG ioctl 0xb BIND_CHANNEL_EX + no-op 3..10).
7. Shader capture stops at the end of a mapped pool instead of throwing.
8. Failed native draws/shaders/compute/MME no longer poison the channel (DmaPusher halted forever
   and fences never signaled -> game freeze). Failing work is skipped, completion still signals.
9. Failed native shaders/compute programs are cached and skipped (was re-capturing 44k
   instructions per draw).
10. QMD scheduler: a rejected compute dispatch still performs its semaphore releases and
    dependent QMDs (channel 1 was stuck waiting on a semaphore 70 -> 210).
11. Ampere->Maxwell shader lowering additions: UMOV from URZ, UISETP signed (bit 73 -> bit 48),
    MUFU UR/imm forms, FFMA UR form, R2P byte select, STG 64/128-bit, new LDG (0x381/0x981),
    predicated CALL.REL.NOINC loop exit without BSYNC.
12. Turing MME: EXTENDED 0x1000/1 = load barrier; `MME_DMA_READ_FIFOED` (methods 0x154/0x155/
    0x158) now reads guest memory into the macro parameter FIFO. MME failures went 4898 -> 0.
13. Native macros deferred until a non-argument method arrives (harmless, kept).
14. Diagnostics: failing shader instruction + neighbors logged; audio BehaviorInfo values logged.

## Status at 2026-10-28 19:30

- Game boots, all 5 GPU channels/queues create, game loop runs, ~190 frames presented per run,
  Eden FPS counter shows ~4 FPS, screen is BLACK.
- 86 native shaders lower OK; 5 still fail (texture forms 0xb60 cube-LOD/descriptor, 0xb63,
  0x526, predicate LUT). ~500 draws per run are skipped.
- Audio renderer rejects every update (BehaviorInfo, error 0x29) — not yet investigated.

## Later log

- 19:31 Screenshot capture tool `tools/ns2/screenshot.ps1` verified (desktop capture readable).

## Second round of fixes (2026-10-28, from 20:30)

Fixes, in order (each verified with tools/ns2/run.ps1; logs in tools/ns2/out/dumps/log-<tag>.txt):

15. Audio renderer: per-update BehaviorInfo magic is "Rev?" (bit 21 set) on the new SDK, init uses
    "REV?". Compare revision numbers, not raw magics. Removed ~600k error lines/run (6% -> 38% speed).
16. Shader lowering: PLOP3 copy from any UPn (bit 6-n of R239), TEX 3D 1-2 component (TEXS 3D/3D.LZ),
    non-scalar TEX ARRAY_CUBE.LL (bit 60 = "scalar"; non-scalar layout {layer,x,y,z}+{lod} per Mesa
    NAK), TLD4 2D -> TLD4S, IPA with multiplier register (0x526 -> Maxwell IPA.MULTIPLY), generic RED
    (0x98e, all ops/types), SHF.R low word with RZ high word. 0 lowering failures / skipped draws.
17. Hang at ~40s: compute macro data RAM (MME DRAM) was shared by every channel of the TSG, so
    channel 2's QMD-ring state was clobbered by channel 3 and its sync object never reached 4.
    KeplerCompute now owns its own TuringMacroInterpreter (code stays shared).
18. Black screen: GPU command 214 reserves the VA ranges where the SDK places render targets
    (6 x 200 MB at 0x81_0249_0000+). They were left unbacked, so every RT there had no device
    address and all clears/draws went nowhere. 214 now allocates a page group, maps it Insecure in
    the alias-code region (outside heap/alias), wraps it in an nvmap handle and maps it at the VA.
    RESULT: first visible UI frames, 60 FPS. Screenshot: docs/ns2/screenshots/first-ui-frame.png
    Text glyphs render as solid blocks (font texture sampling still wrong).

Diagnostics added (all opt-in env vars): EDEN_NATIVE_FRAME_STATS (draws/clears/dispatches/targets per
30 displays), EDEN_NATIVE_SUBMIT_TRACE (every GPFIFO submit), EDEN_NATIVE_DISPLAY_OVERRIDE=<hex DAddr>
(present any RT), trace event 13 (compute macro calls), query trace now flushed (keeps the tail on hang).
Tools (tools/ns2/): run.ps1 (build+run+capture without killing other processes), wincap.ps1 (PrintWindow
capture), threadprof.ps1, rsp.py (GDB-remote client: dump guest threads/memory/disasm at a hang),
pbdecode.py (pushbuffer decoder), setcfg.py (sets qt-config keys incl. the \default flag).
Config note: multi-core CPU mode was used for most of the above.
19. Text/icons drew as solid quads: TEX/TLD/TLD4 bit 79 is .F16 (results packed as half2 pairs, then
    unpacked by HADD2.F32). The lowering ignored it and wrote 32-bit floats, so alpha read as huge.
    Mapped to the Maxwell swizzled forms' precision bit (TEXS/TLDS: bit 59 = 1 means F32, so XOR it
    off; TLD4S: bit 55 = 1 means F16).
    RESULT (23:03): the game shows its mode-select menu - "Normal Mode / Assist Mode / The standard way
    to play. / (+) Options" - at 60 FPS. Screenshot: docs/ns2/screenshots/mode-select-menu.png
    Pressing A (keyboard C) on it moves on to a loading screen with tips.
20. Loading after "Normal Mode" failed with "Too many open files": the VFS keeps up to 8192 host
    files open, but this MinGW build links msvcrt.dll, whose _setmaxstdio caps at 2048. The VFS cache
    now evicts below _getmaxstdio() - 256. Also rate-limited the per-dispatch "Native inline QMD"
    warning and the per-frame puller MemOp errors (log spam).
    Open issue: during the first load (~20 s after selecting Normal Mode) a SparseLargeVector page
    fault ("likely a Dynarmic error") is followed by null-pointer accesses and a guest jump to 0.

## State at 2026-10-28 23:45

- Boots to the mode-select menu ("Normal Mode / Assist Mode / (+) Options") at 100% speed, 60 FPS,
  in single-core mode (multi-core also works). Verified 6+ times.
- Keyboard: A = C, B = X, + = M, - = N, left stick = W/A/S/D.
- Selecting Normal Mode shows the loading screen ("Golden Bananas?!"), but ~15 s into loading a guest
  thread dereferences null in a name-table lookup (main module, PC ~0x808DCDE4 / 0x80869E18,
  caller 0x808DD84C), floods "Unmapped Read/Write", and later jumps to 0. Ruled out: open-file limit
  (fixed), missing romfs files, page-pool exhaustion (no allocation failures), DMA/sync accuracy
  settings, rejected compute shaders, stubbed service calls. Next step would be reverse engineering
  what produced the empty table (EDEN_UNMAPPED_BACKTRACE=1 logs guest backtraces).
- Tried and reverted: backing GPU command 214 from the system pool (starves HLE services, hangs).
- Later narrowing of the load crash (via the GDB stub and breakpoints):
  - The null object is an nn::vfx2 shader program; the crash is in the uniform-block lookup
    (0x80869d40) called from the shader-binding init (0x808dd3fc), whose callers choose one of up
    to three shader variants per effect (0x808e8200 / 0x808e82e0).
  - Exactly one variant check fails, on the loader thread: 0x80869060 returns 3 at 0x80869684
    because nvnProgramSetShaders returns false.
  - The rejected call passes two stages whose GPU code addresses are 0x0 and 0x3600, i.e. raw
    offsets: the memory pool holding that effect's shader code has GPU address 0. The game then
    uses the uninitialised program and dereferences NULL.
  - Next step: find which memory pool that is and why it never gets a GPU mapping.

## Third round (2026-10-29): first load and first gameplay frame

21. First-load crash: IGpuWorker refused maps after 1024 mappings per worker (`0xce01`,
    OutOfResource) and did so silently. NVN's `nvnMemoryPoolInitialize` (sdk 0x82e10ea0) then failed
    inside its map step (0x82e21140); the game ignores the result, so an effect's BNSH shader-code
    pool kept GPU address 0 and `nvnProgramSetShadersExt` got raw offsets. Limits raised to 65536 and
    every rejected worker request is now logged with its words. Traced with NVN's proc-address table
    (GOT 0x82479828 = Initialize, 0x82479858 = GetBufferAddress) and breakpoints on the failure path.
22. Shader lowering added for what the load and first frame use: FMNMX UR form (0xc09); RET when the
    callee returns through the untouched link register (or the high half is cleared one instruction
    early); IADD3 carry-out and IADD3.X carry-in, including uniform forms with UPn emulated in R239;
    IMAD.WIDE.U32 (and uniform 0x2a5); IABS (I2I); 8/16-bit STG/LDG; F2I to S8/U8; AST of RZ / ALD to
    RZ; TEX 2D-array explicit LOD as Maxwell TEX ARRAY_2D.LL; texture descriptors in any constant
    buffer; TLD4 partial masks; any PLOP3 truth table (LOP3 over widened predicates; sources 0xf0 =
    bits 87-90, 0xcc = 77-80, 0xaa = 68-71); BREAK out of a BSSY scope (that scope becomes PBK/BRK);
    uniform registers UR0-UR22 (R216-R238).
23. Storage buffers: up to 32 per stage (the main compute shader binds 18; 16 overflowed and the host
    crashed); unsized bindings stop at the end of their native mapping.
24. Deadlock on the first gameplay frame: graphics (channel 1) and compute (channel 2) hand off through
    semaphores at 0x216aba3000/+4. Channel 2's compute macro 0x44 signals +4 by patching a QMD with
    the inline-to-memory engine (methods 0x60-0x6d) and scheduling it (0xad/0xb0 actions 3 and 7).
    The native compute engine dropped those uploads and the QMD scheduler ignored the release slot at
    word 52. Both are fixed; the game now reaches gameplay (HUD visible, 3D world not drawn, ~5 FPS).
    Found with `EDEN_NATIVE_SEM_WATCH`, `EDEN_NATIVE_STALL_WATCH` and `EDEN_NATIVE_METHOD_TRACE`.
25. Still open: geometry shaders are rejected by the native path (draws skipped); intermittent guest
    memory corruption crash right after Normal Mode is chosen, only seen when A is pressed again during
    the transition (unattended runs use `EDEN_AUTO_PRESS_A=58,4,70`).

## Fourth round (2026-10-29): 3D world in gameplay

26. Freeze at the menu after ~60 s in single-core mode: SDK spinlocks use a TLS preemption protocol
    (+0x100/+0x102) that never makes progress with one host thread. Multi-core mode avoids it.
27. Multi-core crash on entering gameplay (`ExceptionRaised` at 0x80219D40, ~1800 times): the Switch 2
    CPU has ARMv8.1 LSE atomics and Dynarmic only decoded LDADD/LDCLR/LDSET. All eight LDxxx
    register atomics (ADD, CLR, EOR, SET, SMAX, SMIN, UMAX, UMIN) are now one decoder entry
    (`LDATOMIC`) with every size and acquire/release form.
28. Abort 2001-0033, then 2001-0114, at gameplay start: the video codec
    (`nn::codec::video::detail::ipc`) talks to the graphics supervisor. Found by disassembling
    `Initialize` (sdk 0x82b113f0) and `CreateVideoDecoderService` (0x82b11f10):
    - 901 and 1001 return only a result.
    - 902 (905 for system callers) returns the decoder root session; 1002 the encoder root. TIPC
      command 1 on a root creates the decoder/encoder service session.
    - On the service, command 3 returns a copy-handle event before the result; the rest
      (6, 101, 109, 200, 311, ...) are answered with success and zeroed words.
    - 991 is the decoder image pool size query (same request shape as 435/1510).
    - Syncpoint supervisor command 22 returns an event.
    The stand-in decodes nothing (the tutorial video panel stays a flat colour), but the game no
    longer aborts. Unknown supervisor commands are stubbed when `use_auto_stub` is set.
    Handle-0 SVC failures are logged (`returned InvalidHandle`) because a stub handing out handle 0
    caused both aborts.
29. Geometry shaders: the native path now accepts the geometry stage. Lowering added for OUT
    (emit/cut), ISBERD map reads (a copy in Eden's translator), S2R of SR_INVOCATION_ID/INFO, and
    the LEPC + opcode 0x357 prologue (its address result is unused after lowering, so LEPC reads as
    zero and 0x357 is dropped). Maxwell PRMT was not implemented in Eden's translator at all; it is
    now (default mode, all four operand forms).
30. More lowering for gameplay shaders: FSET with a combine predicate; LOP3 with predicate output and
    imm/cbuf/uniform operands; ULOP3 with UPn output; IMNMX with a cbuf operand; I2FP rounding; LEA.HI;
    IMAD negated addend forms and IMAD.X with a zero product; uniform IMAD (0x8a4); F2I to 16 bits and
    rounded 32-bit forms (the Maxwell translator now accepts 8-bit F2I destinations); LDC widths 0-5;
    IADD3 with a uniform operand; SHF.L.HI with a register shift; PRMT with any byte selector; TMML;
    TEX 2D-array depth compare with LOD zero. Offline corpus (shaders dumped with
    `EDEN_NATIVE_SHADER_DUMP_DIR`): 390 of 394 lower; the rest are one ATOM form and three shaders
    reading constant buffer 24.
31. Result: the 3D world renders in gameplay (mining tunnel, DK, rocks). It runs at 5-8 FPS; three
    host threads are saturated and the guest main thread spends most samples waiting on a critical
    section, so the limit looks like CPU emulation throughput.
32. Still open: performance; video decoding; an intermittent fault during the menu-to-loading
    transition (a guest pointer into unmapped space, seen once in five runs); the four remaining
    shader forms.
