package org.otzaria.otzaria;

import android.content.Context;
import android.net.Uri;
import android.os.Bundle;
import android.provider.DocumentsContract;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

// הספק רץ ב־test APK עצמאי; אין בו runtime של Kotlin או מחלקות של אפליקציית היעד.
public final class PdfExportFixture {
    public static final String APP = "org.otzaria.otzaria.pdfexportprobe";
    public static final String AUTHORITY = APP + ".test.documents";
    public static final String CONTROL = APP + ".test.control";
    public static final String ROOT = "fixture-root";
    static final ConcurrentHashMap<String, Document> documents = new ConcurrentHashMap<>();
    static final CopyOnWriteArrayList<String> events = new CopyOnWriteArrayList<>();
    static final AtomicInteger sequence = new AtomicInteger();
    static final AtomicInteger readers = new AtomicInteger();
    static volatile Bundle options = new Bundle();
    static volatile CountDownLatch release = new CountDownLatch(1);
    static File directory;

    private PdfExportFixture() {}

    static Uri tree() {
        return DocumentsContract.buildTreeDocumentUri(AUTHORITY, ROOT);
    }

    static final class Document {
        final String id;
        final String name;
        final File file;
        final Bundle options;
        final CountDownLatch closed = new CountDownLatch(1);
        volatile boolean opened;
        volatile long bytes;
        volatile boolean deleted;
        volatile String readerError;

        Document(String id, String name, File file, Bundle options) {
            this.id = id;
            this.name = name;
            this.file = file;
            this.options = options;
        }
    }

    static void initialize(Context context) {
        directory = new File(context.getFilesDir(), "pdf-export-provider-fixture");
        check(directory.isDirectory() || directory.mkdirs(), "Could not create fixture directory");
    }

    static void reset(Bundle configuration) {
        check(readers.get() == 0, "Previous pipe reader is still active");
        release.countDown();
        documents.clear();
        File[] files = directory.listFiles();
        if (files != null) {
            for (File file : files) check(file.delete(), "Could not clear fixture file");
        }
        events.clear();
        options = new Bundle(configuration);
        release = new CountDownLatch(1);
        File existing = new File(directory, "existing");
        try (FileOutputStream output = new FileOutputStream(existing)) {
            output.write("Existing user document must remain unchanged".getBytes(StandardCharsets.UTF_8));
        } catch (IOException error) {
            throw new IllegalStateException("Could not create fixture input", error);
        }
        documents.put("existing", new Document("existing", "existing.pdf", existing, new Bundle()));
    }

    static void awaitRelease() {
        try {
            check(release.await(20, TimeUnit.SECONDS), "Fixture gate was not released");
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Fixture gate interrupted", error);
        }
    }

    static String snapshot() {
        try {
            JSONObject result = new JSONObject();
            result.put("events", new JSONArray(events));
            result.put("readers", readers.get());
            ArrayList<Document> sorted = new ArrayList<>(documents.values());
            sorted.sort(Comparator.comparing(document -> document.id));
            JSONArray rows = new JSONArray();
            for (Document document : sorted) {
                JSONObject row = new JSONObject();
                row.put("id", document.id);
                row.put("name", document.name);
                row.put("bytes", document.options.getBoolean("pipe") ? document.bytes : document.file.length());
                row.put("opened", document.opened);
                row.put("closed", document.closed.getCount() == 0);
                row.put("deleted", document.deleted);
                row.put("readerError", document.readerError == null ? JSONObject.NULL : document.readerError);
                if (document.file.exists()) row.put("sha256", sha256(document.file));
                rows.put(row);
            }
            result.put("documents", rows);
            return result.toString();
        } catch (JSONException error) {
            throw new IllegalStateException("Could not serialize fixture state", error);
        }
    }

    private static String sha256(File file) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (FileInputStream input = new FileInputStream(file)) {
                byte[] buffer = new byte[65536];
                int count;
                while ((count = input.read(buffer)) >= 0) digest.update(buffer, 0, count);
            }
            StringBuilder result = new StringBuilder(64);
            for (byte value : digest.digest()) {
                result.append(Character.forDigit((value >>> 4) & 15, 16));
                result.append(Character.forDigit(value & 15, 16));
            }
            return result.toString();
        } catch (NoSuchAlgorithmException | IOException error) {
            throw new IllegalStateException("Could not hash fixture document", error);
        }
    }

    static void check(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }
}
