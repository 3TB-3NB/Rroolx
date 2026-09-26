export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = Roblox

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = executor

executor_FILES = \
    Sources/Entry.m \
    Sources/Executor.m \
    Sources/LuaHook.m \
    Sources/LuauRuntime.m \
    Sources/Stealth.m \
    Sources/UIOverlay.m

executor_HEADERS = \
    Sources/LuauTypes.h \
    Sources/LuauRuntime.h

executor_CFLAGS = \
    -fobjc-arc \
    -fvisibility=hidden \
    -O2 \
    -Wno-unused-variable \
    -Wno-deprecated-declarations

executor_FRAMEWORKS = \
    Foundation \
    UIKit \
    CoreGraphics \
    QuartzCore

executor_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries/

include $(THEOS_MAKE_PATH)/library.mk
