TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

# Build as a plain dylib — no CydiaSubstrate/libhooker dependency so it
# loads on non-jailbroken devices sideloaded via AltStore/Sideloadly.
LIBRARY_NAME = FilzaApplySandboxExt

FilzaApplySandboxExt_FILES = Tweak.m MCMBridge.m MCMFilzaIntegration.m PosterBoardFeature.m UpdateChecker.m \
    LiquidGlassUI.m SandboxExtIssue.m \
    apfs_own.m

FilzaApplySandboxExt_CFLAGS = -I$(PWD)/compat -I$(PWD) -I$(PWD)/XPF/src -I$(PWD)/XPF/external/ChOma/include \
    -fobjc-arc \
    -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable \
    -Wno-incompatible-pointer-types -Wno-incompatible-pointer-types-discards-qualifiers \
    -Wno-deprecated-declarations -Wno-nonportable-include-path -Wno-format \
    -Wno-arc-performSelector-leaks

FilzaApplySandboxExt_CCFLAGS = $(FilzaApplySandboxExt_CFLAGS)
FilzaApplySandboxExt_OBJCFLAGS = $(FilzaApplySandboxExt_CFLAGS)
FilzaApplySandboxExt_OBJCCFLAGS = $(FilzaApplySandboxExt_CFLAGS)

FilzaApplySandboxExt_FRAMEWORKS = UIKit Foundation IOKit CoreFoundation Security
FilzaApplySandboxExt_PRIVATE_FRAMEWORKS = IOSurface
FilzaApplySandboxExt_LIBRARIES = z sandbox

include $(THEOS_MAKE_PATH)/library.mk
