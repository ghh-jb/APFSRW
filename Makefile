TARGET := iphone:clang:15.2:15.2

include $(THEOS)/makefiles/common.mk

TOOL_NAME = APFSRW

APFSRW_FILES = main.m
APFSRW_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-incompatible-pointer-types-discards-qualifiers -Wno-tautological-constant-out-of-range-compare
APFSRW_FRAMEWORKS = IOKit 
APFSRW_CODESIGN_FLAGS = -Sentitlements.plist
APFSRW_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
