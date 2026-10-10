# Otzaria Download Assistant for Linux (C + GTK3) — docs/download_assistant.md,
# "מסייע ההורדה ל-Linux". Links only GTK3 and what it pulls (GLib/GIO, Pango,
# Cairo, GDK) plus libc: Otzaria's own packages depend on nothing more.
#
#   make                 build/Otzaria-Download-Assistant (fetches the pinned art once)
#   make test            unit tests (fixtures, JSON, HTTP, markers, assembly, texts)
#   make check-needed    fail when the binary links anything unexpected
#   make dist DIST_ARCH=x64|arm64
#
# The release tag is embedded from $OTZARIA_ASSISTANT_RELEASE_TAG only.

CC ?= cc
PKG_CONFIG ?= pkg-config
BUILD ?= build
DIST_ARCH ?= x64

GTK_CFLAGS := $(shell $(PKG_CONFIG) --cflags gtk+-3.0)
GTK_LIBS := $(shell $(PKG_CONFIG) --libs gtk+-3.0)
GIO_CFLAGS := $(shell $(PKG_CONFIG) --cflags gio-2.0)
GIO_LIBS := $(shell $(PKG_CONFIG) --libs gio-2.0)
GLIB_COMPILE_RESOURCES ?= $(shell $(PKG_CONFIG) --variable=glib_compile_resources gio-2.0)

CFLAGS ?= -O2 -g
override CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter \
  -D_FILE_OFFSET_BITS=64 -DG_LOG_DOMAIN='"otzaria"' -I$(BUILD) -I.
# Drops libraries pkg-config lists but the code never calls (harfbuzz, atk, zlib).
override LDFLAGS += -Wl,--as-needed

CORE := otz_common.c json.c manifest.c selection.c http.c release.c paths.c \
  download.c assemble.c texts.c
APP := $(CORE) widgets.c ui.c main.c
HEADERS := $(wildcard *.h)

BIN := $(BUILD)/Otzaria-Download-Assistant
TEST_BIN := $(BUILD)/test_runner
UI_TEST_BIN := $(BUILD)/ui_test_runner
FIXTURES := $(abspath ../fixtures)

all: $(BIN)

$(BUILD)/build_info.h: FORCE
	@sh gen_build_info.sh $@

$(BUILD)/core/%.o: %.c $(HEADERS) $(BUILD)/build_info.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(GIO_CFLAGS) -c $< -o $@

$(BUILD)/app/%.o: %.c $(HEADERS) $(BUILD)/build_info.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(GTK_CFLAGS) -c $< -o $@

# The art is not in the repository: fetch_art.sh brings the pinned, SHA-256 checked
# version, embedded as a GResource so the binary stays a single file.
ART := $(BUILD)/art
PIN := ../../../installer/assistant_art.pin.json

$(ART)/.pinned-sha256: $(PIN) fetch_art.sh
	sh fetch_art.sh $(ART)
	@touch $@

# The window icon is not part of the pinned art: it is shared with the Windows .ico.
$(ART)/app_icon.png: ../../../installer/download_assistant_icon_256.png $(ART)/.pinned-sha256
	cp $< $@

$(BUILD)/art.gresource.xml: $(ART)/.pinned-sha256 $(ART)/app_icon.png
	@{ echo '<?xml version="1.0" encoding="UTF-8"?>'; \
	  echo '<gresources><gresource prefix="/org/otzaria/assistant">'; \
	  for f in $(ART)/*.png; do echo "<file>$$(basename $$f)</file>"; done; \
	  echo '</gresource></gresources>'; } > $@

$(BUILD)/art_resources.c: $(BUILD)/art.gresource.xml
	$(GLIB_COMPILE_RESOURCES) --sourcedir=$(ART) --generate-source --c-name=otz_art \
	  --target=$@ $<

$(BUILD)/app/art_resources.o: $(BUILD)/art_resources.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -w $(GIO_CFLAGS) -c $< -o $@

$(BIN): $(APP:%.c=$(BUILD)/app/%.o) $(BUILD)/app/art_resources.o
	$(CC) $(LDFLAGS) -o $@ $^ $(GTK_LIBS) -lm

$(BUILD)/core/test_main.o: tests/test_main.c $(HEADERS) $(BUILD)/build_info.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(GIO_CFLAGS) -DOTZ_FIXTURES_DIR='"$(FIXTURES)"' -c $< -o $@

$(TEST_BIN): $(CORE:%.c=$(BUILD)/core/%.o) $(BUILD)/core/test_main.o
	$(CC) $(LDFLAGS) -o $@ $^ $(GIO_LIBS)

test: $(TEST_BIN) test-build-info
	$(TEST_BIN)

$(UI_TEST_BIN): tests/test_ui.c ui.c $(CORE:%.c=$(BUILD)/app/%.o) $(BUILD)/app/widgets.o $(BUILD)/app/art_resources.o
	$(CC) $(CFLAGS) $(GTK_CFLAGS) -DOTZ_FIXTURES_DIR='"$(FIXTURES)"' -o $@ $< \
	  $(filter %.o,$^) $(LDFLAGS) $(GTK_LIBS) -lm

test-ui: $(UI_TEST_BIN)
	@for scale in 1 2; do \
	  GDK_SCALE=$$scale xvfb-run -a -s "-screen 0 1920x1080x24" $(UI_TEST_BIN) || exit $$?; \
	done

# The same tests under AddressSanitizer/UBSan, in a separate build directory.
SANITIZE := -fsanitize=address,undefined -fno-omit-frame-pointer
test-asan:
	$(MAKE) BUILD=$(BUILD)-asan CFLAGS="-O1 -g $(SANITIZE)" LDFLAGS="$(SANITIZE)" \
	  $(BUILD)-asan/test_runner
	UBSAN_OPTIONS=halt_on_error=1 $(BUILD)-asan/test_runner

# "+" must survive intact; a quote must be refused.
test-build-info:
	@OTZARIA_ASSISTANT_RELEASE_TAG='0.10.3+143' sh gen_build_info.sh $(BUILD)/tag_test/ok.h
	@grep -q '"0.10.3+143"' $(BUILD)/tag_test/ok.h
	@if OTZARIA_ASSISTANT_RELEASE_TAG='0.10.3"x' sh gen_build_info.sh \
	  $(BUILD)/tag_test/bad.h 2>/dev/null; then \
	  echo "gen_build_info.sh accepted a quote"; exit 1; fi
	@echo "build info: ok"

ALLOWED_NEEDED := ^(libgtk-3|libgdk-3|libpango-1\.0|libpangocairo-1\.0|libcairo|libcairo-gobject|libgdk_pixbuf-2\.0|libgio-2\.0|libgobject-2\.0|libglib-2\.0|libc|libm|libpthread|libdl|librt|ld-linux[-a-z0-9_]*)\.so

check-needed: $(BIN)
	@readelf -d $(BIN) | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' > $(BUILD)/needed.txt
	@cat $(BUILD)/needed.txt
	@if grep -Ev '$(ALLOWED_NEEDED)' $(BUILD)/needed.txt; then \
	  echo "unexpected NEEDED entries (listed above)"; exit 1; fi

dist: $(BIN)
	rm -rf $(BUILD)/dist
	mkdir -p $(BUILD)/dist/Otzaria-Download-Assistant
	install -s -m 755 $(BIN) $(BUILD)/dist/Otzaria-Download-Assistant/Otzaria-Download-Assistant
	tar -C $(BUILD)/dist -czf $(BUILD)/Otzaria-Download-Assistant-linux-$(DIST_ARCH).tar.gz \
	  Otzaria-Download-Assistant

clean:
	rm -rf $(BUILD)

.PHONY: all test test-asan test-build-info check-needed dist clean FORCE test-ui
