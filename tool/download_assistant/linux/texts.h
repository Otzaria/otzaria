/* Every visible text of the interface, in Hebrew and English. The wording is
 * the Windows assistant's (installer/download_assistant*.iss, CustomMessages). */
#pragma once

#include <glib.h>

#define OTZ_STRING_KEYS(X)                                                       \
  X(APP_TITLE) X(WELCOME_SUBTITLE) X(WELCOME_NOTE) X(START_BUTTON)               \
  X(NEXT) X(BACK) X(START) X(FINISH) X(CANCEL) X(CLOSE) X(OK)                    \
  X(STOP_DOWNLOAD) X(RETRY) X(RESUME) X(OPEN_DOWNLOADS) X(TECH_DETAILS)          \
  X(STEP_OF) X(CONNECT_TITLE) X(CONNECT_DESC) X(CONNECTING_PROGRESS)             \
  X(MODE_TITLE) X(MODE_DESC) X(MODE_THIS) X(MODE_THIS_DESC) X(THIS_DEB)          \
  X(THIS_RPM) X(THIS_PORTABLE) X(THIS_ARM) X(MODE_OTHER) X(MODE_OTHER_DESC)      \
  X(LIST_OR) X(VERSION_TO_DOWNLOAD) X(OTZARIA_VERSION) X(OTHER_TITLE)            \
  X(OTHER_DESC) X(OTHER_HINT) X(TARGET_ARM) X(HINT_MAC) X(HINT_ANDROID)          \
  X(HINT_ARM) X(HINT_X64) X(FORMAT_DEB) X(FORMAT_RPM) X(FORMAT_PORTABLE)         \
  X(PRESET_TITLE) X(PRESET_DESC) X(PRESET_HINT) X(PRESET_FULL_INDEXED)           \
  X(PRESET_FULL_INDEXED_DESC) X(PRESET_FULL) X(PRESET_FULL_DESC)                 \
  X(PRESET_BASIC) X(PRESET_BASIC_DESC) X(PRESET_UPDATE) X(PRESET_UPDATE_DESC)    \
  X(PRESET_CUSTOM) X(PRESET_CUSTOM_DESC) X(CARD_SIZE) X(REQUIRED_TAG)            \
  X(CUSTOM_DESC) X(CUSTOM_HINT) X(FOLDER_TITLE) X(FOLDER_DESC) X(FOLDER_HINT)    \
  X(FOLDER_FALLBACK_NOTE) X(BROWSE) X(CHOOSE) X(READY_TITLE) X(READY_DESC)       \
  X(READY_HINT) X(ROW_VERSION) X(ROW_WHAT) X(ROW_FOR) X(ROW_SAVED_IN)            \
  X(ROW_FILE) X(ROW_FOLDER) X(DOWNLOADING_VERSION) X(DOWNLOAD_DESC)              \
  X(DOWNLOADING_ITEM) X(DOWNLOADED_OF) X(TIME_LEFT) X(SIZE_OF) X(WORK_TITLE)     \
  X(WORK_DESC) X(PREPARING) X(CHECKING_CACHED) X(JOINING_FILES)                  \
  X(CHECKING_JOINED) X(COPYING_TO) X(FINISHED_TITLE) X(GUIDE_THIS_FILE)          \
  X(GUIDE_OTHER_FILE) X(GUIDE_THIS_FOLDER) X(GUIDE_OTHER_FOLDER)                 \
  X(GUIDE_RUN_EXE) X(GUIDE_JOIN) X(PREPARED_FILES) X(OPEN_HINT_EXE)              \
  X(OPEN_HINT_DMG) X(OPEN_HINT_PACKAGE) X(OPEN_HINT_APK) X(OPEN_HINT_ARCHIVE)    \
  X(REVEAL_FILE) X(REVEAL_FOLDER) X(OPEN_FOLDER) X(OFFLINE_TITLE)                \
  X(OFFLINE_BODY) X(LOAD_FAILED_BODY) X(STOPPED_TITLE) X(STOPPED_BODY)           \
  X(RUN_FAILED_BODY) X(TLS_TITLE) X(TLS_BODY) X(NO_TARGET_TITLE)                 \
  X(NO_TARGET_TEXT) X(NOTHING_TITLE) X(NOTHING_TEXT) X(FOLDER_BAD_TITLE)         \
  X(FOLDER_BAD_FALLBACK) X(FOLDER_BAD_TEXT) X(SPACE_TITLE) X(SPACE_TEXT)         \
  X(SPACE_YES) X(EXIT_TITLE) X(EXIT_MESSAGE) X(EXIT_YES) X(EXIT_NO)              \
  X(CONNECT_STOP_TITLE) X(CONNECT_STOP_TEXT) X(CONNECT_STOP_YES)                 \
  X(CONNECT_STOP_NO) X(STOP_TITLE) X(STOP_TEXT) X(STOP_YES) X(STOP_NO)           \
  X(ERR_FILE_UNAVAILABLE) X(ERR_CANNOT_CONNECT) X(ERR_CANNOT_READ_LIST)          \
  X(ERR_CANNOT_PREPARE) X(ERR_COPY) X(ERR_SAVE) X(ERR_DAMAGED)                   \
  X(ERR_WRITE_JOINED) X(OUTPUT_SUBFOLDER) X(DURATION_UNDER_MINUTE)               \
  X(DURATION_HOUR) X(DURATION_TWO_HOURS) X(DURATION_HOURS) X(DURATION_MINUTE)    \
  X(DURATION_MINUTES) X(DURATION_JOIN)

typedef enum {
#define OTZ_KEY(name) S_##name,
  OTZ_STRING_KEYS(OTZ_KEY)
#undef OTZ_KEY
  S_COUNT
} OtzString;

/* Hebrew when the interface language (LANGUAGE, LC_ALL, LC_MESSAGES, LANG) is
 * Hebrew, otherwise English. OTZARIA_ASSISTANT_LANG=he|en overrides it. */
gboolean otz_detect_english(void);
void otz_set_english(gboolean english);
gboolean otz_english(void);

const char *otz_tr(OtzString key);
/* otz_tr with %1, %2, %3 replaced by the NULL-terminated arguments. */
char *otz_trf(OtzString key, ...) G_GNUC_NULL_TERMINATED;
/* The Hebrew text whatever the language: the core reports sentences in it. */
const char *otz_tr_hebrew(OtzString key);
/* A sentence the core reports (always Hebrew) in the interface language. */
const char *otz_tr_message(const char *hebrew);

/* An LTR value (size, speed, version, path) inside Hebrew text: isolated,
 * or "37 MB" shows reversed. English text is returned as is. */
char *otz_ltr(const char *text);
/* Hebrew: every line opens with RLM, so a line that starts with a Latin word
 * stays right to left, and RLM after ", " keeps a Latin list in reading order. */
char *otz_bidi(const char *text);

char *otz_size_text(gint64 bytes);
char *otz_speed_text(double bytes_per_second);
char *otz_duration_text(double seconds);
