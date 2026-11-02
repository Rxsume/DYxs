#
#  DYxs —— 抖音 UI 增强插件（模块化 hook 框架）
#

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = Aweme

DK_VERSION := $(shell awk -F': *' '$$1 == "Version" { print $$2; exit }' control)
DYXS_PACKAGE_SCHEME ?= $(if $(THEOS_PACKAGE_SCHEME),$(THEOS_PACKAGE_SCHEME),rootful)

ifeq ($(strip $(DK_VERSION)),)
$(error Missing Version in control)
endif

ifeq ($(DYXS_PACKAGE_SCHEME),rootful)
unexport THEOS_PACKAGE_SCHEME
DYXS_PACKAGE_SUFFIX = arm-rootful
else ifeq ($(DYXS_PACKAGE_SCHEME),rootless)
export THEOS_PACKAGE_SCHEME = rootless
DYXS_PACKAGE_SUFFIX = arm64-rootless
else ifeq ($(DYXS_PACKAGE_SCHEME),roothide)
export THEOS_PACKAGE_SCHEME = roothide
DYXS_PACKAGE_SUFFIX = arm64e-roothide
else
$(error Unsupported DYXS_PACKAGE_SCHEME: $(DYXS_PACKAGE_SCHEME))
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYxs
DYxs_FILES = $(shell find src -type f \( -name '*.m' -o -name '*.mm' -o -name '*.x' -o -name '*.xm' -o -name '*.c' -o -name '*.cc' -o -name '*.cpp' \) | sort)
DYxs_INCLUDE_DIRS = $(shell find src -type d | sort)
DYxs_CFLAGS = -fobjc-arc -w -fmodules-cache-path=$(CURDIR)/debug/details/cache/module-cache $(addprefix -I,$(DYxs_INCLUDE_DIRS)) -DDK_VERSION=@\"$(DK_VERSION)\"
DYxs_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics Photos PhotosUI ImageIO UniformTypeIdentifiers AudioToolbox AVFAudio AVFoundation CoreMedia MediaToolbox Accelerate
DYxs_LDFLAGS += -lz
DYxs_LOGOS_DEFAULT_GENERATOR = internal

export THEOS_STRICT_LOGOS = 0
export ERROR_ON_WARNINGS = 0
export LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	@rm -rf .theos packages

package-rootful::
	@rm -rf .theos
	@$(MAKE) all package DYXS_PACKAGE_SCHEME=rootful FINALPACKAGE=1

package-rootless::
	@rm -rf .theos
	@$(MAKE) all package DYXS_PACKAGE_SCHEME=rootless FINALPACKAGE=1

package-roothide::
	@if [ -d "$(THEOS_VENDOR_MODULE_PATH)/roothide" ] || [ -d "$(THEOS_MODULE_PATH)/roothide" ]; then \
		rm -rf .theos; \
		$(MAKE) all package DYXS_PACKAGE_SCHEME=roothide FINALPACKAGE=1; \
	elif [ "$$GITHUB_ACTIONS" = "true" ]; then \
		echo "error: roothide Theos package scheme is required in CI."; \
		exit 1; \
	else \
		echo "warning: roothide Theos package scheme not found; skipped roothide package."; \
	fi

all-packages::
	@rm -rf packages
	@mkdir -p packages
	@$(MAKE) package-rootful FINALPACKAGE=1
	@$(MAKE) package-rootless FINALPACKAGE=1
	@$(MAKE) package-roothide FINALPACKAGE=1

before-package::
ifneq ($(THEOS_PACKAGE_INSTALL_PREFIX),)
	@mkdir -p "$(_THEOS_SCHEME_STAGE)"
endif

after-package::
	@mkdir -p packages
	@DEB=$$(cat "$(_THEOS_LOCAL_DATA_DIR)/last_package" 2>/dev/null || true); \
	 OUT="packages/DYxs_$(DK_VERSION)_$(DYXS_PACKAGE_SUFFIX).deb"; \
	 if [ -n "$$DEB" ] && [ -f "$$DEB" ]; then mv -f "$$DEB" "$$OUT"; fi
	@if [ "$(DYXS_PACKAGE_SCHEME)" = "rootful" ]; then \
		DYLIB="$(THEOS_OBJ_DIR)/DYxs.dylib"; \
		if [ -n "$$DYLIB" ]; then cp -f "$$DYLIB" packages/DYxs.dylib; fi; \
	fi
	@echo "==> 成品: packages/DYxs_$(DK_VERSION)_$(DYXS_PACKAGE_SUFFIX).deb"
