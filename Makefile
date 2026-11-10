ARCHS := arm64
TARGET := iphone:clang:latest:15.0
FINALPACKAGE = 1

TWEAK_NAME = SSLKillSwitch2
SSLKillSwitch2_FILES = SSLKillSwitch/SSLKillSwitch.m
SSLKillSwitch2_CFLAGS = -fobjc-arc -ISSLKillSwitch/fishhook -Wno-error -Wno-format -Wno-everything
SSLKillSwitch2_FRAMEWORKS = Security

SSLKillSwitch2_FILES += SSLKillSwitch/fishhook/fishhook.c
SSLKillSwitch2_LOGOS_DEFAULT_GENERATOR = internal
SSLKillSwitch2_CFLAGS += -DUSE_NSLOG

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
