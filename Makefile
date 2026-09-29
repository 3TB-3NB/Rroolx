ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Roblox

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = krb

krb_FILES = Sources/Entry.m
krb_CFLAGS = -fobjc-arc
krb_FRAMEWORKS = Foundation UIKit
krb_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries/

include $(THEOS_MAKE_PATH)/library.mk
