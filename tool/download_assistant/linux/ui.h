/* The assistant window (docs/download_assistant.md, "מסייע ההורדה ל-Linux"). */
#pragma once

#include <glib.h>

typedef struct {
  gboolean self_test;
  gboolean tls_ok;
  /* Dev only: see main.c --help. */
  const char *dev_manifest;
  const char *dev_auto_preset;
  const char *dev_platform;
  const char *dev_output;
  const char *dev_screenshot;
} OtzUiOptions;

/* Runs the assistant; returns the process exit code. */
int otz_ui_run(const OtzUiOptions *options);
