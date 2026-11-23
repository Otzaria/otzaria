package org.otzaria.otzaria;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;

// ערוץ הפיקוח קיים רק ב־test APK ופתוח רק לחתימת ה־probe; הרשאת DocumentsProvider לא משתנה.
public final class PdfExportControlProvider extends ContentProvider {
    @Override public boolean onCreate() {
        PdfExportFixture.initialize(getContext());
        return true;
    }

    @Override public Bundle call(String method, String arg, Bundle extras) {
        getContext().enforceCallingOrSelfPermission(PdfExportFixture.APP + ".CONTROL", "PDF fixture control requires the probe signature");
        switch (method) {
            case "reset": PdfExportFixture.reset(extras != null ? extras : new Bundle()); break;
            case "release": PdfExportFixture.release.countDown(); break;
            case "grant":
                PdfExportFixture.events.add("test-grant");
                getContext().grantUriPermission(PdfExportFixture.APP, PdfExportFixture.tree(),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
                break;
            case "snapshot": break;
            default: throw new IllegalArgumentException("Unknown fixture command: " + method);
        }
        Bundle result = new Bundle();
        result.putString("tree", PdfExportFixture.tree().toString());
        result.putString("snapshot", PdfExportFixture.snapshot());
        return result;
    }

    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] selectionArgs, String sortOrder) { return null; }
    @Override public String getType(Uri uri) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { return null; }
    @Override public int delete(Uri uri, String selection, String[] selectionArgs) { return 0; }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] selectionArgs) { return 0; }
}
