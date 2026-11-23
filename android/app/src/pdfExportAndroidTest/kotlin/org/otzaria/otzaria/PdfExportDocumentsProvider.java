package org.otzaria.otzaria;

import android.database.Cursor;
import android.database.MatrixCursor;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;
import android.provider.DocumentsProvider;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.TimeUnit;

public final class PdfExportDocumentsProvider extends DocumentsProvider {
    private static final String[] DOCUMENT_COLUMNS = {
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_FLAGS,
        DocumentsContract.Document.COLUMN_SIZE,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED
    };

    @Override public boolean onCreate() {
        PdfExportFixture.initialize(getContext());
        return true;
    }

    @Override public Cursor queryRoots(String[] projection) {
        String[] columns = projection != null ? projection : new String[] {
            DocumentsContract.Root.COLUMN_ROOT_ID, DocumentsContract.Root.COLUMN_DOCUMENT_ID,
            DocumentsContract.Root.COLUMN_TITLE, DocumentsContract.Root.COLUMN_FLAGS,
            DocumentsContract.Root.COLUMN_MIME_TYPES
        };
        MatrixCursor cursor = new MatrixCursor(columns);
        MatrixCursor.RowBuilder row = cursor.newRow();
        for (String column : columns) {
            Object value;
            switch (column) {
                case DocumentsContract.Root.COLUMN_ROOT_ID: value = "pdf-export"; break;
                case DocumentsContract.Root.COLUMN_DOCUMENT_ID: value = PdfExportFixture.ROOT; break;
                case DocumentsContract.Root.COLUMN_TITLE: value = "PDF export fixture"; break;
                case DocumentsContract.Root.COLUMN_FLAGS:
                    value = DocumentsContract.Root.FLAG_SUPPORTS_CREATE | DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD; break;
                case DocumentsContract.Root.COLUMN_MIME_TYPES: value = "application/pdf"; break;
                default: value = null;
            }
            row.add(column, value);
        }
        return cursor;
    }

    @Override public Cursor queryDocument(String documentId, String[] projection) throws FileNotFoundException {
        String[] columns = projection != null ? projection : DOCUMENT_COLUMNS;
        PdfExportFixture.Document document = PdfExportFixture.documents.get(documentId);
        if (!PdfExportFixture.ROOT.equals(documentId) && document != null && document.options.getBoolean("nameFailure") &&
            Arrays.equals(columns, new String[] {DocumentsContract.Document.COLUMN_DISPLAY_NAME})) {
            throw new FileNotFoundException("Fixture name query denied");
        }
        MatrixCursor cursor = new MatrixCursor(columns);
        addDocument(cursor, documentId);
        return cursor;
    }

    @Override public Cursor queryChildDocuments(String parentDocumentId, String[] projection, String sortOrder) throws FileNotFoundException {
        PdfExportFixture.check(PdfExportFixture.ROOT.equals(parentDocumentId), "Unknown parent");
        MatrixCursor cursor = new MatrixCursor(projection != null ? projection : DOCUMENT_COLUMNS);
        ArrayList<PdfExportFixture.Document> sorted = new ArrayList<>(PdfExportFixture.documents.values());
        sorted.sort(Comparator.comparing(document -> document.name));
        for (PdfExportFixture.Document document : sorted) {
            if (!document.deleted) addDocument(cursor, document.id);
        }
        return cursor;
    }

    private void addDocument(MatrixCursor cursor, String id) throws FileNotFoundException {
        boolean root = PdfExportFixture.ROOT.equals(id);
        PdfExportFixture.Document document = root ? null : PdfExportFixture.documents.get(id);
        if (!root && document == null) throw new FileNotFoundException(id);
        int flags = root ? DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE :
            DocumentsContract.Document.FLAG_SUPPORTS_WRITE |
                ("unsupported".equals(document.options.getString("deleteMode")) ? 0 : DocumentsContract.Document.FLAG_SUPPORTS_DELETE);
        MatrixCursor.RowBuilder row = cursor.newRow();
        for (String column : cursor.getColumnNames()) {
            Object value;
            switch (column) {
                case DocumentsContract.Document.COLUMN_DOCUMENT_ID: value = id; break;
                case DocumentsContract.Document.COLUMN_DISPLAY_NAME: value = root ? "PDF export fixture" : document.name; break;
                case DocumentsContract.Document.COLUMN_MIME_TYPE: value = root ? DocumentsContract.Document.MIME_TYPE_DIR : "application/pdf"; break;
                case DocumentsContract.Document.COLUMN_FLAGS: value = flags; break;
                case DocumentsContract.Document.COLUMN_SIZE: value = root ? 0L : document.file.length(); break;
                case DocumentsContract.Document.COLUMN_LAST_MODIFIED: value = root ? 0L : document.file.lastModified(); break;
                default: value = null;
            }
            row.add(column, value);
        }
    }

    @Override public boolean isChildDocument(String parentDocumentId, String documentId) {
        return PdfExportFixture.ROOT.equals(parentDocumentId) && PdfExportFixture.documents.containsKey(documentId);
    }

    @Override public String createDocument(String parentDocumentId, String mimeType, String displayName) throws FileNotFoundException {
        PdfExportFixture.check(PdfExportFixture.ROOT.equals(parentDocumentId) && "application/pdf".equals(mimeType), "Unexpected create request");
        Bundle options = new Bundle(PdfExportFixture.options);
        PdfExportFixture.events.add("create-enter");
        if (options.getBoolean("blockCreate")) PdfExportFixture.awaitRelease();
        if (options.getBoolean("createFailure")) throw new FileNotFoundException("Fixture create failure");
        if (options.getBoolean("createReturnsParent")) return parentDocumentId;
        String id = "copy-" + PdfExportFixture.sequence.incrementAndGet();
        Set<String> used = new HashSet<>();
        for (PdfExportFixture.Document document : PdfExportFixture.documents.values()) used.add(document.name);
        String actualName = displayName;
        String stem = displayName.endsWith(".pdf") ? displayName.substring(0, displayName.length() - 4) : displayName;
        int suffix = 2;
        while (used.contains(actualName)) actualName = stem + " (" + suffix++ + ").pdf";
        File file = new File(PdfExportFixture.directory, id);
        try {
            PdfExportFixture.check(file.createNewFile(), "Fixture document already exists");
        } catch (IOException error) {
            throw fileError(error);
        }
        PdfExportFixture.documents.put(id, new PdfExportFixture.Document(id, actualName, file, options));
        PdfExportFixture.events.add("create-return:" + id);
        return id;
    }

    @Override public ParcelFileDescriptor openDocument(String documentId, String mode, CancellationSignal signal) throws FileNotFoundException {
        PdfExportFixture.events.add("open-request:" + documentId);
        PdfExportFixture.Document document = PdfExportFixture.documents.get(documentId);
        if (document == null) throw new FileNotFoundException(documentId);
        if ("r".equals(mode)) return ParcelFileDescriptor.open(document.file, ParcelFileDescriptor.MODE_READ_ONLY);
        PdfExportFixture.check(!"existing".equals(documentId), "Existing user document must not be opened for writing");
        PdfExportFixture.check("w".equals(mode), "The export path must support a nonseekable writer");
        if (document.options.getBoolean("openFailure")) throw new FileNotFoundException("Fixture output open failure");
        document.opened = true;
        PdfExportFixture.events.add("write-open:" + documentId);
        try {
            if (!document.options.getBoolean("pipe")) {
                return ParcelFileDescriptor.open(document.file, ParcelFileDescriptor.MODE_WRITE_ONLY | ParcelFileDescriptor.MODE_TRUNCATE,
                    new Handler(Looper.getMainLooper()), error -> {
                        document.readerError = error == null ? null : error.getMessage();
                        document.closed.countDown();
                        PdfExportFixture.events.add("write-close:" + documentId);
                    });
            }
            ParcelFileDescriptor[] pipe = ParcelFileDescriptor.createReliablePipe();
            PdfExportFixture.readers.incrementAndGet();
            new Thread(() -> readPipe(document, pipe[0]), "pdf-export-fixture-pipe").start();
            return pipe[1];
        } catch (IOException error) {
            throw fileError(error);
        }
    }

    private void readPipe(PdfExportFixture.Document document, ParcelFileDescriptor pipe) {
        try (ParcelFileDescriptor.AutoCloseInputStream input = new ParcelFileDescriptor.AutoCloseInputStream(pipe);
             FileOutputStream output = new FileOutputStream(document.file)) {
            byte[] buffer = new byte[65536];
            boolean gated = false;
            int count;
            while ((count = input.read(buffer)) >= 0) {
                output.write(buffer, 0, count);
                document.bytes += count;
                if (!gated && document.options.getBoolean("blockWrite")) {
                    gated = true;
                    PdfExportFixture.events.add("write-gate:" + document.id);
                    PdfExportFixture.awaitRelease();
                }
                long failAfter = document.options.getLong("failAfter");
                if (failAfter > 0 && document.bytes >= failAfter) {
                    pipe.closeWithError("Fixture pipe failed after positive bytes");
                    break;
                }
            }
        } catch (Exception error) {
            document.readerError = error.getMessage();
        } finally {
            document.closed.countDown();
            PdfExportFixture.readers.decrementAndGet();
            PdfExportFixture.events.add("write-close:" + document.id);
        }
    }

    @Override public void deleteDocument(String documentId) throws FileNotFoundException {
        PdfExportFixture.events.add("delete-request:" + documentId);
        PdfExportFixture.check(!"existing".equals(documentId), "Existing user document must not be deleted");
        PdfExportFixture.Document document = PdfExportFixture.documents.get(documentId);
        if (document == null) throw new FileNotFoundException(documentId);
        PdfExportFixture.events.add("delete:" + documentId);
        try {
            if (document.opened && !document.closed.await(10, TimeUnit.SECONDS)) {
                throw new FileNotFoundException("Writer did not close before cleanup");
            }
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            throw fileError(error);
        }
        if ("unsupported".equals(document.options.getString("deleteMode"))) {
            throw new UnsupportedOperationException("Fixture does not support deletion");
        }
        if ("failed".equals(document.options.getString("deleteMode"))) {
            throw new FileNotFoundException("Fixture deletion refused");
        }
        PdfExportFixture.check(document.file.delete(), "Fixture document was not deleted");
        document.deleted = true;
    }

    private static FileNotFoundException fileError(Exception error) {
        FileNotFoundException result = new FileNotFoundException(error.getMessage());
        result.initCause(error);
        return result;
    }
}
