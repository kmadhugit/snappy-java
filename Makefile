
include Makefile.common

MVN:=mvn
SBT:=./sbt

all: snappy

SNAPPY_OUT:=$(TARGET)/snappy-$(SNAPPY_VERSION)-$(os_arch)
SNAPPY_ARCHIVE:=$(TARGET)/snappy-$(SNAPPY_VERSION).tar.gz
SNAPPY_CC:=snappy-sinksource.cc snappy-stubs-internal.cc snappy.cc
SNAPPY_SRC_DIR:=$(TARGET)/snappy-$(SNAPPY_VERSION)
SNAPPY_SRC:=$(addprefix $(SNAPPY_SRC_DIR)/,$(SNAPPY_CC))
SNAPPY_GIT_REPO_URL:=https://github.com/google/snappy
SNAPPY_GIT_REV:=2d99bd14d471664758e4dfdf81b44f413a7353fd # 1.1.4
SNAPPY_UNPACKED:=$(TARGET)/snappy-extracted.log
SNAPPY_GIT_UNPACKED:=$(TARGET)/snappy-git-extracted.log
SNAPPY_SOURCE_CONFIGURED:=$(TARGET)/snappy-configure.log

BITSHUFFLE_ARCHIVE:=$(TARGET)/bitshuffle-$(BITSHUFFLE_VERSION).tar.gz
BITSHUFFLE_C:=bitshuffle_core.c iochain.c
BITSHUFFLE_SRC_DIR:=$(TARGET)/bitshuffle-$(BITSHUFFLE_VERSION)/src
BITSHUFFLE_SRC:=$(addprefix $(BITSHUFFLE_SRC_DIR)/,$(BITSHUFFLE_C))
BITSHUFFLE_UNPACKED:=$(TARGET)/bitshuffle-extracted.log

$(BITSHUFFLE_ARCHIVE):
	@mkdir -p $(@D)
	curl -L -o$@ https://github.com/kiyo-masui/bitshuffle/archive/$(BITSHUFFLE_VERSION).tar.gz

$(BITSHUFFLE_UNPACKED): $(BITSHUFFLE_ARCHIVE)
	$(TAR) xvfz $< -C $(TARGET)
	touch $@

$(BITSHUFFLE_SRC): $(BITSHUFFLE_UNPACKED)

$(SNAPPY_OUT)/%.o: $(BITSHUFFLE_SRC_DIR)/%.c
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) $(CXXFLAGS_BITSHUFFLE) -c $< -o $@

SNAPPY_OBJ:=$(addprefix $(SNAPPY_OUT)/,$(patsubst %.cc,%.o,$(SNAPPY_CC)) $(patsubst %.c,%.o,$(BITSHUFFLE_C)) SnappyNative.o BitShuffleNative.o)

CXXFLAGS:=$(CXXFLAGS) -I$(SNAPPY_SRC_DIR) -I$(BITSHUFFLE_SRC_DIR) -Ofast -mcpu=power8 -mtune=power8

ifndef CXXFLAGS_BITSHUFFLE
  ifeq ($(OS_NAME)-$(OS_ARCH),Linux-x86_64)
	# SSE2 is supported in all the x86_64 platforms and AVX2 is only supported
        # in the small part of them. gcc in linux/x86_64 typically enables SSE2 by default though,
	# we explicitly set flags below to make this precondition clearer.
	CXXFLAGS_BITSHUFFLE:=-U__AVX2__ -msse2
  else
	# Undefined macros to generate a platform-independent binary
	CXXFLAGS_BITSHUFFLE:=-U__AVX2__ -U__SSE2__
  endif
endif

ifeq ($(OS_NAME),SunOS)
	TAR:= gtar
else
ifeq ($(OS_NAME),AIX)
	TAR:= gtar
else
	TAR:= tar
endif
endif

$(SNAPPY_ARCHIVE):
	@mkdir -p $(@D)
	curl -L -o$@ https://github.com/google/snappy/releases/download/$(SNAPPY_VERSION)/snappy-$(SNAPPY_VERSION).tar.gz

$(SNAPPY_UNPACKED): $(SNAPPY_ARCHIVE)
	$(TAR) xvfz $< -C $(TARGET)
	touch $@
	cd  $(SNAPPY_SRC_DIR) && ./configure

$(SNAPPY_GIT_UNPACKED):
	rm -rf $(SNAPPY_SRC_DIR)
	@mkdir -p $(SNAPPY_SRC_DIR)
	git clone $(SNAPPY_GIT_REPO_URL) $(SNAPPY_SRC_DIR)
	git --git-dir=$(SNAPPY_SRC_DIR)/.git --work-tree=$(SNAPPY_SRC_DIR) checkout -b local/snappy-$(SNAPPY_VERSION) $(SNAPPY_GIT_REV)
	cd $(SNAPPY_SRC_DIR) && git fetch origin pull/27/head:pull27 && git checkout pull27
	touch $@

$(SNAPPY_SOURCE_CONFIGURED): $(SNAPPY_GIT_UNPACKED)
	cd $(SNAPPY_SRC_DIR) && ./autogen.sh && ./configure
	touch $@

jni-header: $(SNAPPY_SOURCE_CONFIGURED) $(BITSHUFFLE_UNPACKED) $(SRC)/org/xerial/snappy/SnappyNative.h $(SRC)/org/xerial/snappy/BitShuffleNative.h

$(TARGET)/jni-classes/org/xerial/snappy/SnappyNative.class: $(SRC)/org/xerial/snappy/SnappyNative.java
	@mkdir -p $(TARGET)/jni-classes
	$(JAVAC) -source 1.7 -target 1.7 -d $(TARGET)/jni-classes -sourcepath $(SRC) $<

$(SRC)/org/xerial/snappy/SnappyNative.h: $(TARGET)/jni-classes/org/xerial/snappy/SnappyNative.class
	$(JAVAH) -force -classpath $(TARGET)/jni-classes -o $@ org.xerial.snappy.SnappyNative

$(TARGET)/jni-classes/org/xerial/snappy/BitShuffleNative.class: $(SRC)/org/xerial/snappy/BitShuffleNative.java
	@mkdir -p $(TARGET)/jni-classes
	$(JAVAC) -source 1.7 -target 1.7 -d $(TARGET)/jni-classes -sourcepath $(SRC) $<

$(SRC)/org/xerial/snappy/BitShuffleNative.h: $(TARGET)/jni-classes/org/xerial/snappy/BitShuffleNative.class
	$(JAVAH) -force -classpath $(TARGET)/jni-classes -o $@ org.xerial.snappy.BitShuffleNative

$(SNAPPY_SRC): $(SNAPPY_GIT_UNPACKED)

$(SNAPPY_OUT)/%.o: $(SNAPPY_SRC_DIR)/%.cc
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(SNAPPY_OUT)/SnappyNative.o: $(SRC)/org/xerial/snappy/SnappyNative.cpp $(SRC)/org/xerial/snappy/SnappyNative.h
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(SNAPPY_OUT)/BitShuffleNative.o: $(SRC)/org/xerial/snappy/BitShuffleNative.cpp $(SRC)/org/xerial/snappy/BitShuffleNative.h
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(SNAPPY_OUT)/$(LIBNAME): $(SNAPPY_OBJ)
	$(CXX) $(CXXFLAGS) -o $@ $+ $(LINKFLAGS)
    # Workaround for strip Protocol error when using VirtualBox on Mac
	cp $@ /tmp/$(@F)
	$(STRIP) /tmp/$(@F)
	cp /tmp/$(@F) $@

clean-native:
	rm -rf $(SNAPPY_OUT)

clean:
	rm -rf $(TARGET)

NATIVE_DIR:=src/main/resources/org/xerial/snappy/native/$(OS_NAME)/$(OS_ARCH)
NATIVE_TARGET_DIR:=$(TARGET)/classes/org/xerial/snappy/native/$(OS_NAME)/$(OS_ARCH)
NATIVE_DLL:=$(NATIVE_DIR)/$(LIBNAME)

snappy-jar-version:=snappy-java-$(shell perl -npe "s/version in ThisBuild\s+:=\s+\"(.*)\"/\1/" version.sbt | sed -e "/^$$/d")

native: jni-header $(NATIVE_DLL)
snappy: native $(TARGET)/$(snappy-jar-version).jar

native-all: win32 win64 mac64 native-arm linux32 linux64 linux-ppc64le linux-aarch64

$(NATIVE_DLL): $(SNAPPY_SOURCE_CONFIGURED) $(SNAPPY_OUT)/$(LIBNAME)
	@mkdir -p $(@D)
	cp $(SNAPPY_OUT)/$(LIBNAME) $@
	@mkdir -p $(NATIVE_TARGET_DIR)
	cp $(SNAPPY_OUT)/$(LIBNAME) $(NATIVE_TARGET_DIR)/$(LIBNAME)

package: $(TARGET)/$(snappy-jar-version).jar

$(TARGET)/$(snappy-jar-version).jar:
	$(SBT) package

test: $(NATIVE_DLL)
	$(SBT) test

DOCKER_RUN_OPTS:=--rm

win32: jni-header
	./docker/dockcross-windows-x86 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=i686-w64-mingw32.static- OS_NAME=Windows OS_ARCH=x86'

win64: jni-header
	./docker/dockcross-windows-x64 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=x86_64-w64-mingw32.static- OS_NAME=Windows OS_ARCH=x86_64'

# deprecated
mac32: jni-header
	$(MAKE) native OS_NAME=Mac OS_ARCH=x86

mac64: jni-header
	docker run -it $(DOCKER_RUN_OPTS) -v $$PWD:/workdir -e CROSS_TRIPLE=x86_64-apple-darwin multiarch/crossbuild make clean-native native OS_NAME=Mac OS_ARCH=x86_64

linux32: jni-header
	docker run $(DOCKER_RUN_OPTS) -ti -v $$PWD:/work xerial/centos5-linux-x86_64-pic bash -c 'make clean-native native OS_NAME=Linux OS_ARCH=x86'

linux64: jni-header
	docker run $(DOCKER_RUN_OPTS) -ti -v $$PWD:/work xerial/centos5-linux-x86_64-pic bash -c 'make clean-native native OS_NAME=Linux OS_ARCH=x86_64'

freebsd64:
	$(MAKE) native OS_NAME=FreeBSD OS_ARCH=x86_64

# For ARM
native-arm: linux-arm linux-armv6 linux-armv7 linux-android-arm

linux-arm: jni-header
	./docker/dockcross-armv5 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=arm-linux-gnueabi- OS_NAME=Linux OS_ARCH=arm'

linux-armv6: jni-header
	./docker/dockcross-armv6 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=arm-linux-gnueabihf- OS_NAME=Linux OS_ARCH=armv6'

linux-armv7: jni-header
	./docker/dockcross-armv7 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=arm-linux-gnueabihf- OS_NAME=Linux OS_ARCH=armv7'

linux-android-arm: jni-header
	./docker/dockcross-android-arm -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=/usr/arm-linux-androideabi/bin/arm-linux-androideabi- OS_NAME=Linux OS_ARCH=android-arm'

linux-ppc64le: jni-header
	./docker/dockcross-ppc64le -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=powerpc64le-linux-gnu- OS_NAME=Linux OS_ARCH=ppc64le'

linux-ppc64: jni-header
	./docker/dockcross-ppc64 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=powerpc64-linux-gnu- OS_NAME=Linux OS_ARCH=ppc64'

linux-aarch64: jni-header
	./docker/dockcross-aarch64 -a $(DOCKER_RUN_OPTS) bash -c 'make clean-native native CROSS_PREFIX=aarch64-linux-gnu- OS_NAME=Linux OS_ARCH=aarch64'

javadoc:
	$(SBT) doc

install-m2:
	$(SBT) publishM2
