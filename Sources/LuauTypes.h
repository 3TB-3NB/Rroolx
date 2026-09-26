// language: Objective-C, file: LuauTypes.h, runtime: iOS 15+ arm64
// *تعريف lua_State + TValue + الإزاحات المؤكدة من Delta binary*

#ifndef LuauTypes_h
#define LuauTypes_h

#include <stdint.h>

// ==== TValue (16 bytes) ====
typedef struct {
    union {
        void    *gc;
        void    *p;
        double   n;
        int      b;
        float    v[2];
    } value;
    int32_t  extra;
    int32_t  tt;
} TValue;

typedef TValue *StkId;

// ==== CallInfo ====
typedef struct CallInfo {
    StkId     base;
    StkId     func;
    StkId     top;
    void     *savedpc;
    int32_t   nresults;
    uint32_t  flags;
} CallInfo;

// ==== lua_State — الإزاحات مؤكدة من Delta binary (libgloop.dylib) ====
// تم التحقق من 0x18 (base) مباشرة من Ghidra
typedef struct lua_State {
    uint8_t   tt;
    uint8_t   marked;
    uint8_t   memcat;
    uint8_t   _pad1[5];
    uint8_t   status;
    uint8_t   activememcat;
    uint8_t   isactive;
    uint8_t   singlestep;
    uint8_t   _pad2[4];
    StkId       top;              // 0x10 ← مؤكد
    StkId       base;             // 0x18 ← مؤكد
    void       *global;           // 0x20
    CallInfo   *ci;               // 0x28
    StkId       stack_last;       // 0x30
    StkId       stack;            // 0x38
    CallInfo   *end_ci;           // 0x40
    CallInfo   *base_ci;          // 0x48
    int32_t     stacksize;        // 0x50
    int32_t     size_ci;          // 0x54
    uint16_t    nCcalls;          // 0x58
    uint16_t    baseCcalls;       // 0x5A
    int32_t     cachedslot;       // 0x5C
    void       *gt;               // 0x60
    void       *openupval;        // 0x68
    void       *gclist;           // 0x70
    void       *namecall;         // 0x78
    void       *userdata;         // 0x80
} lua_State;

// ==== الإزاحات — مؤكدة من التحليل ====
#define LUA_STATE_TOP_OFFSET          0x10
#define LUA_STATE_BASE_OFFSET         0x18  // ⭐ مؤكد من Ghidra
#define LUA_STATE_GLOBAL_OFFSET       0x20
#define LUA_STATE_CI_OFFSET           0x28
#define LUA_STATE_STACK_LAST_OFFSET   0x30
#define LUA_STATE_STACK_OFFSET        0x38
#define LUA_STATE_GT_OFFSET           0x60
#define LUA_STATE_USERDATA_OFFSET     0x80

// ==== TValue types ====
#define LUA_TNIL           0
#define LUA_TBOOLEAN       1
#define L byteUA_TLIGHTUSERDATA 2
#define LUA_TNUMBER        3
#define LUA_TVECTOR        4
#define LUA_TSTRING        5
#define LUA_TTABLE         6
#define LUA_TFUNCTION      7
#define LUA_TUSERDATA      8
#define LUA_TTHREAD        9
#define LUA_TBUFFER        10

// ==== Pseudo indexes ====
#define LUA_REGISTRYINDEX (-1001000)
#define LUA_GLOBALSINDEX  (-1001002)

#endif
