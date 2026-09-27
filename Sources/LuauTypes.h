// language: Objective-C, file: LuauTypes.h, runtime: iOS 15+ arm64

#ifndef LuauTypes_h
#define LuauTypes_h

#include <stdint.h>

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

typedef struct CallInfo {
    StkId     base;
    StkId     func;
    StkId     top;
    void     *savedpc;
    int32_t   nresults;
    uint32_t  flags;
} CallInfo;

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
    StkId       top;
    StkId       base;
    void       *global;
    CallInfo   *ci;
    StkId       stack_last;
    StkId       stack;
    CallInfo   *end_ci;
    CallInfo   *base_ci;
    int32_t     stacksize;
    int32_t     size_ci;
    uint16_t    nCcalls;
    uint16_t    baseCcalls;
    int32_t     cachedslot;
    void       *gt;
    void       *openupval;
    void       *gclist;
    void       *namecall;
    void       *userdata;
} lua_State;

#define LUA_STATE_TOP_OFFSET          0x10
#define LUA_STATE_BASE_OFFSET         0x18
#define LUA_STATE_GLOBAL_OFFSET       0x20
#define LUA_STATE_CI_OFFSET           0x28
#define LUA_STATE_STACK_LAST_OFFSET   0x30
#define LUA_STATE_STACK_OFFSET        0x38
#define LUA_STATE_GT_OFFSET           0x60
#define LUA_STATE_USERDATA_OFFSET     0x80

#define LUA_TNIL           0
#define LUA_TBOOLEAN       1
#define LUA_TLIGHTUSERDATA 2
#define LUA_TNUMBER        3
#define LUA_TVECTOR        4
#define LUA_TSTRING        5
#define LUA_TTABLE         6
#define LUA_TFUNCTION      7
#define LUA_TUSERDATA      8
#define LUA_TTHREAD        9
#define LUA_TBUFFER        10

#define LUA_REGISTRYINDEX (-1001000)
#define LUA_GLOBALSINDEX  (-1001002)

#endif
