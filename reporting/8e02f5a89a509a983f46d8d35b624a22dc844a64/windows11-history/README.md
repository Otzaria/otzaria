# Windows 11 clipboard history evidence

Product: `8e02f5a89a509a983f46d8d35b624a22dc844a64` (tree `f7acec410894ecbd0bafe6aa0654cd8fb3c2c87e`).

The [native Windows run](https://github.com/Otzaria/otzaria/actions/runs/42320691502) executed the actual Flutter report dialog on Windows 11 Enterprise 10.0.26200 ARM64, with an x64 process, in a Debug build using a dedicated integration entrypoint and the product's AppReportDialog. It exercised Windows' real history popup and selected an older item A while B was the current clipboard.

Both trace settings completed seven cases: three negative controls and four history selections (text/image, focused/unfocused). The clipboard-format observer was disabled in every case. The final assertions check the exact title, a single attached image, all 64 RGBA bytes of its 4×4 pixels, focus, foreground and released keys. Text without field focus must leave the title unchanged. The loaded clipboard DLL hash matches the DLL built from source and packaged for this run.

## Screenshots

The 16 PNG files are exact, unedited desktop captures. Their original artifact paths, lengths, dimensions and SHA-256 values are in [manifest.json](manifest.json).

**Capture timing matters:** each `after` screenshot is taken by the controller immediately after Windows changes the clipboard to the chosen A item. Dart subsequently waits for the asynchronous handler and makes the final image assertions. An `after` screenshot can therefore precede the appearance of the image thumbnail. The completed form-state and pixel assertions are recorded in the JSON evidence; the image screenshots alone do not prove that decoding has finished.

These desktop captures show the history selection. They do not establish low-window accessibility; separate [form screenshots](../report-forms-qa) cover the UI layouts.

## JSON and provenance

The three `*-projection.json` files contain a bounded, allowlisted projection of the source JSON, including each original file's hash and byte length. They are not presented as complete original files. The source artifacts and their pinned SHA-256 values are recorded in the manifest.

The [read-only evidence transport](https://github.com/Otzaria/otzaria/actions/runs/42324776245) passed its nine self-checks before reading the pinned artifacts. It did not modify the H1 run, the product or any pixels, and its `h1Acceptance: not-evaluated` flag is retained. An independent reviewer approved product `8e02f5a8` after reviewing the code, runtime assertions, all 16 PNG byte hashes and all 16 images. The review is recorded in the manifest. No installed release package was tested.

Windows Server 2025 supplied the build and prerequisite evidence: three controls passed, and the four unsupported history cases remained explicit failures. That exception is not used for Windows 11.

No claim is made for Win+V on Windows 10 or on a separate native x64 Windows 11 host.
