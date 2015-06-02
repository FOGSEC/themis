#
# Copyright (c) 2015 Cossack Labs Limited
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#CC = clang
SRC_PATH = src
BIN_PATH = build
OBJ_PATH = build/obj
TEST_SRC_PATH = tests
TEST_OBJ_PATH = build/tests/obj
TEST_BIN_PATH = build/tests

CFLAGS += -I$(SRC_PATH) -fPIC 

ifeq ($(ENGINE),)
	ENGINE=libressl
endif

#default engine
ifeq ($(PREFIX),)
PREFIX = /usr
endif

#engine selection block
ifneq ($(ENGINE),)
ifeq ($(ENGINE),openssl)
	CRYPTO_ENGINE_DEF = OPENSSL
	CRYPTO_ENGINE_PATH=openssl
else ifeq ($(ENGINE),libressl)
	CRYPTO_ENGINE_DEF = LIBRESSL	
	CRYPTO_ENGINE_PATH=openssl
else
	ERROR = $(error error: engine $(ENGINE) unsupported...)
endif
endif
#end of engine selection block

CRYPTO_ENGINE = $(SRC_PATH)/soter/$(CRYPTO_ENGINE_PATH)
CFLAGS += -D$(CRYPTO_ENGINE_DEF)

ifneq ($(ENGINE_INCLUDE_PATH),)
	CRYPTO_ENGINE_INCLUDE_PATH = $(ENGINE_INCLUDE_PATH)
endif
ifneq ($(ENGINE_LIB_PATH),)
	CRYPTO_ENGINE_LIB_PATH = $(ENGINE_LIB_PATH)
endif

PHP_VERSION := $(shell php --version 2>/dev/null)
RUBY_GEM_VERSION := $(shell gem --version 2>/dev/null)
PIP_VERSION := $(shell pip --version 2>/dev/null)
PYTHON_VERSION := $(shell python --version 2>&1)
ifdef PIP_VERSION
PIP_THEMIS_INSTALL := $(shell pip freeze |grep themis)
endif

SHARED_EXT = so

UNAME=$(shell uname)
IS_LINUX = $(shell $(CC) -dumpmachine 2>&1 | $(EGREP) -c "linux")
IS_MINGW = $(shell $(CC) -dumpmachine 2>&1 | $(EGREP) -c "mingw")
IS_CLANG_COMPILER = $(shell $(CC) --version 2>&1 | $(EGREP) -i -c "clang version")

ifeq ($(shell uname),Darwin)
SHARED_EXT = dylib
ifneq ($(SDK),)
SDK_PLATFORM_VERSION=$(shell xcrun --sdk $(SDK) --show-sdk-platform-version)
XCODE_BASE=$(shell xcode-select --print-path)
CC=$(XCODE_BASE)/usr/bin/gcc
BASE=$(shell xcrun --sdk $(SDK) --show-sdk-platform-path)
SDK_BASE=$(shell xcrun --sdk $(SDK) --show-sdk-path)
FRAMEWORKS=$(SDK_BASE)/System/Library/Frameworks/
SDK_INCLUDES=$(SDK_BASE)/usr/include
CFLAFS += -isysroot $(SDK_BASE) 
endif
ifneq ($(ARCH),)
CFLAFS += -arch $(ARCH)
endif
endif

ifdef DEBUG
# Making debug build for now
	CFLAGS += -DDEBUG -g
endif

# Should pay attention to warnings (some may be critical for crypto-enabled code (ex. signed-unsigned mismatch)
CFLAGS += -Werror -Wno-switch

ifndef ERROR
include src/soter/soter.mk
include src/themis/themis.mk
endif


all: err themis_static themis_shared

test_all: err test

soter_static: $(SOTER_OBJ)
	$(AR) rcs $(BIN_PATH)/lib$(SOTER_BIN).a $(SOTER_OBJ)

soter_shared: $(SOTER_OBJ)
	$(CC) -shared -o $(BIN_PATH)/lib$(SOTER_BIN).$(SHARED_EXT) $(SOTER_OBJ) $(LDFLAGS)

themis_static: soter_static $(THEMIS_OBJ)
	$(AR) rcs $(BIN_PATH)/lib$(THEMIS_BIN).a $(THEMIS_OBJ)

themis_shared: soter_shared $(THEMIS_OBJ)
	$(CC) -shared -o $(BIN_PATH)/lib$(THEMIS_BIN).$(SHARED_EXT) $(THEMIS_OBJ) -L$(BIN_PATH) -l$(SOTER_BIN)

$(OBJ_PATH)/%.o: $(SRC_PATH)/%.c
	mkdir -p $(@D)
	$(CC) $(CFLAGS) -c $< -o $@

$(TEST_OBJ_PATH)/%.o: $(TEST_SRC_PATH)/%.c
	mkdir -p $(@D)
	$(CC) $(CFLAGS) -DNIST_STS_EXE_PATH=$(realpath $(NIST_STS_DIR)) -I$(TEST_SRC_PATH) -c $< -o $@

include tests/test.mk

err: ; $(ERROR)

clean: nist_rng_test_suite
	rm -rf $(BIN_PATH)

install: err all
	mkdir -p $(PREFIX)/include/themis $(PREFIX)/include/soter $(PREFIX)/lib
	install $(SRC_PATH)/soter/*.h $(PREFIX)/include/soter
	install $(SRC_PATH)/themis/*.h $(PREFIX)/include/themis
	install $(BIN_PATH)/*.a $(PREFIX)/lib
	install $(BIN_PATH)/*.$(SHARED_EXT) $(PREFIX)/lib

phpthemis_uninstall:
	cd src/wrappers/themis/php && make distclean

rubythemis_uninstall:
ifdef RUBY_GEM_VERSION
	gem uninstall themis
endif

pythonthemis_uninstall: 
ifdef PIP_THEMIS_INSTALL
	pip -q uninstall -y themis
endif


uninstall: phpthemis_uninstall rubythemis_uninstall pythonthemis_uninstall
	rm -rf $(PREFIX)/include/themis
	rm -rf $(PREFIX)/include/soter
	rm -f $(PREFIX)/lib/libsoter.a
	rm -f $(PREFIX)/lib/libthemis.a
	rm -f $(PREFIX)/lib/libsoter.so
	rm -f $(PREFIX)/lib/libthemis.so
	rm -f $(PREFIX)/lib/libsoter.dylib
	rm -f $(PREFIX)/lib/libthemis.dylib

phpthemis_install: install
ifdef PHP_VERSION
	cd src/wrappers/themis/php && phpize && ./configure && make install
else
	@echo "Error: php not found"
	@exit 1
endif

rubythemis_install: install
ifdef RUBY_GEM_VERSION
	cd src/wrappers/themis/ruby && gem build themis.gemspec && gem install ./*.gem
else
	@echo "Error: ruby gem not found"
	@exit 1
endif

pythonthemis_install: install
ifdef PYTHON_VERSION
	cd src/wrappers/themis/python/ && python setup.py install
else
	@echo "Error: python not found"
	@exit 1
endif