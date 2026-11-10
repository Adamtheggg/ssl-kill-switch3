
ARCHS := arm64 arm64e

TWEAK_NAME = SSLKillSwitch2
SSLKillSwitch2_FILES = SSLKillSwitch/SSLKillSwitch.m
SSLKillSwitch2_CFLAGS = -fobjc-arc
SSLKillSwitch2_CFLAGS += -ISSLKillSwitch/fishhook
SSLKillSwitch2_FRAMEWORKS = Security

ifndef FISHHOOK

ifdef ROOTLESS
$(info Build as a ROOTLESS Substrate Tweak)
THEOS_PACKAGE_SCHEME=rootless
PACKAGE_BUILDNAME := rootless
else ifdef ROOTHIDE
$(info Build as a ROOTHIDE Substrate Tweak)
THEOS_PACKAGE_SCHEME=roothide
PACKAGE_BUILDNAME := roothide
else
$(info Build as a ROOTFUL Substrate Tweak)
PACKAGE_BUILDNAME := rootful
endif

ifneq ($(findstring DEBUG,$(THEOS_SCHEMA)),)
PACKAGE_BUILDNAME := $(PACKAGE_BUILDNAME)debug
endif

SSLKillSwitch2_CFLAGS += -DSUBSTRATE_BUILD

else

$(info Build as a FishHook Tweak)
SSLKillSwitch2_FILES += SSLKillSwitch/fishhook/fishhook.c
SSLKillSwitch2_LOGOS_DEFAULT_GENERATOR = internal
SSLKillSwitch2_CFLAGS += -DUSE_NSLOG

endif

include $(THEOS)/makefiles/common.mk

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
