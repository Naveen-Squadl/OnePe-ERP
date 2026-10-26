package com.onepe.onepe_pos;

import android.Manifest;
import android.annotation.TargetApi;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.UriPermission;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.DocumentsContract;
import android.provider.MediaStore;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * "onepe/backup" method channel used by lib/services/offline_queue.dart: copies of offline bills in
 * Download/OnePe/OfflineBills. Files there survive "Clear storage" and uninstall.
 *
 * Access, best first:
 * - Android 10+ with the folder chosen once (Storage Access Framework, persisted permission): read, write and
 *   delete every file in it – also ones left by an earlier install – so recovery and clean-up are automatic.
 * - Android 10+ without it: MediaStore Downloads, no permission; only this install's files are visible.
 * - Android 9 and older: plain files with WRITE_EXTERNAL_STORAGE.
 * The folder chooser / permission prompt itself runs in MainActivity ("pickFolder").
 */
final class OfflineBackup implements MethodChannel.MethodCallHandler {
    static final String NAME = "onepe/backup";
    static final String FOLDER = "Download/OnePe/OfflineBills";
    private static final String DIR = "OnePe/OfflineBills";
    private static final String PREFIX = "bill_";

    private final Context context;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    OfflineBackup(Context context) {
        this.context = context.getApplicationContext();
    }

    static boolean needsLegacyPermission(Context context) {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED;
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        String name = call.argument("name");
        switch (call.method) {
            case "status":
                run(result, this::folderName);
                return;
            case "write":
                String json = call.argument("json");
                run(result, () -> write(name, json));
                return;
            case "delete":
                run(result, () -> delete(name));
                return;
            case "list":
                run(result, this::list);
                return;
            default:
                result.notImplemented();
        }
    }

    private interface Job {
        Object run() throws IOException;
    }

    private void run(MethodChannel.Result result, Job job) {
        worker.execute(() -> {
            try {
                Object value = job.run();
                main.post(() -> result.success(value));
            } catch (Throwable e) {
                String msg = e.getMessage() == null ? e.toString() : e.getMessage();
                main.post(() -> result.error("BACKUP_FAILED", msg, null));
            }
        });
    }

    // ---- folder access ----------------------------------------------------------------------------

    /** Name of the folder the app can fully manage, or null (then the user should be asked once). */
    private String folderName() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return needsLegacyPermission(context) ? null : FOLDER;
        Uri tree = grantedTree(context);
        if (tree == null) return null;
        String id = DocumentsContract.getTreeDocumentId(tree); // e.g. "primary:Download/OnePe/OfflineBills"
        return id.contains(":") ? id.substring(id.indexOf(':') + 1) : id;
    }

    static Uri grantedTree(Context context) {
        for (UriPermission p : context.getContentResolver().getPersistedUriPermissions()) {
            if (p.isReadPermission() && p.isWritePermission() && DocumentsContract.isTreeUri(p.getUri())) return p.getUri();
        }
        return null;
    }

    /** Folder chooser opened at Download/OnePe/OfflineBills (created first so it can be selected). */
    @TargetApi(Build.VERSION_CODES.Q)
    static Intent pickIntent(Context context) {
        ensureFolder(context);
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:" + FOLDER));
        return intent;
    }

    /** Keeps the newly chosen folder and drops older grants. */
    static void keepFolder(Context context, Uri tree) {
        ContentResolver cr = context.getContentResolver();
        int flags = Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION;
        cr.takePersistableUriPermission(tree, flags);
        for (UriPermission p : cr.getPersistedUriPermissions()) {
            if (!p.getUri().equals(tree)) cr.releasePersistableUriPermission(p.getUri(), flags);
        }
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private static void ensureFolder(Context context) {
        File dir = new File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), DIR);
        if (dir.exists()) return;
        ContentValues values = new ContentValues();
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, "README.txt");
        values.put(MediaStore.MediaColumns.MIME_TYPE, "text/plain");
        values.put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath());
        Uri uri = context.getContentResolver().insert(collection(), values);
        if (uri == null) return;
        try (OutputStream out = context.getContentResolver().openOutputStream(uri)) {
            if (out != null) {
                out.write(("OnePe ERP keeps a copy of bills made without internet here until they are uploaded.\n" +
                        "Do not delete bill_*.json files while the app shows bills waiting to sync.\n").getBytes(StandardCharsets.UTF_8));
            }
        } catch (IOException ignored) {
            // The folder exists now either way.
        }
    }

    // ---- operations -------------------------------------------------------------------------------

    private boolean write(String name, String json) throws IOException {
        byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            if (needsLegacyPermission(context)) return false;
            File dir = legacyDir();
            if (!dir.isDirectory() && !dir.mkdirs()) return false;
            try (OutputStream out = new FileOutputStream(new File(dir, name))) {
                out.write(bytes);
            }
            return true;
        }
        ContentResolver cr = context.getContentResolver();
        Uri tree = grantedTree(context);
        Uri uri;
        if (tree != null) {
            uri = findInTree(cr, tree, name);
            if (uri == null) uri = DocumentsContract.createDocument(cr, treeDocument(tree), "application/json", name);
        } else {
            uri = findInMediaStore(cr, name);
            if (uri == null) {
                ContentValues values = new ContentValues();
                values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
                values.put(MediaStore.MediaColumns.MIME_TYPE, "application/json");
                values.put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath());
                uri = cr.insert(collection(), values);
            }
        }
        if (uri == null) return false;
        try (OutputStream out = cr.openOutputStream(uri, "wt")) {
            if (out == null) return false;
            out.write(bytes);
        }
        return true;
    }

    private boolean delete(String name) throws IOException {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            File f = new File(legacyDir(), name);
            return !f.exists() || f.delete();
        }
        ContentResolver cr = context.getContentResolver();
        Uri tree = grantedTree(context);
        if (tree != null) {
            Uri uri = findInTree(cr, tree, name);
            if (uri != null) return DocumentsContract.deleteDocument(cr, uri);
        }
        Uri uri = findInMediaStore(cr, name);
        return uri == null || cr.delete(uri, null, null) > 0;
    }

    /** Contents of every bill_*.json in the folder (empty without full folder access). */
    private List<String> list() throws IOException {
        List<String> out = new ArrayList<>();
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            File[] files = needsLegacyPermission(context) ? null : legacyDir().listFiles();
            if (files == null) return out;
            for (File f : files) {
                if (isBill(f.getName())) {
                    try (InputStream in = new FileInputStream(f)) {
                        out.add(read(in));
                    }
                }
            }
            return out;
        }
        Uri tree = grantedTree(context);
        if (tree == null) return out;
        ContentResolver cr = context.getContentResolver();
        for (Map.Entry<String, Uri> e : children(cr, tree).entrySet()) {
            if (!isBill(e.getKey())) continue;
            try (InputStream in = cr.openInputStream(e.getValue())) {
                if (in != null) out.add(read(in));
            }
        }
        return out;
    }

    // ---- helpers ----------------------------------------------------------------------------------

    private static boolean isBill(String name) {
        return name != null && name.startsWith(PREFIX) && name.endsWith(".json");
    }

    private static String read(InputStream in) throws IOException {
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        byte[] chunk = new byte[8192];
        for (int n; (n = in.read(chunk)) > 0; ) buf.write(chunk, 0, n);
        return buf.toString("UTF-8");
    }

    private static File legacyDir() {
        return new File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), DIR);
    }

    private static Uri treeDocument(Uri tree) {
        return DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));
    }

    /** display name → document uri of the files directly in the chosen folder. */
    private static Map<String, Uri> children(ContentResolver cr, Uri tree) {
        Map<String, Uri> out = new HashMap<>();
        Uri uri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));
        String[] columns = {DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME};
        try (Cursor c = cr.query(uri, columns, null, null, null)) {
            while (c != null && c.moveToNext()) out.put(c.getString(1), DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0)));
        }
        return out;
    }

    private static Uri findInTree(ContentResolver cr, Uri tree, String name) {
        return children(cr, tree).get(name);
    }

    /** The file this install created (without folder access, files from an earlier install are not visible). */
    @TargetApi(Build.VERSION_CODES.Q)
    private static Uri findInMediaStore(ContentResolver cr, String name) {
        String where = MediaStore.MediaColumns.RELATIVE_PATH + "=? AND " + MediaStore.MediaColumns.DISPLAY_NAME + "=?";
        try (Cursor c = cr.query(collection(), new String[]{MediaStore.MediaColumns._ID}, where, new String[]{relativePath(), name}, null)) {
            if (c == null || !c.moveToFirst()) return null;
            return Uri.withAppendedPath(collection(), String.valueOf(c.getLong(0)));
        }
    }

    @TargetApi(Build.VERSION_CODES.Q)
    private static Uri collection() {
        return MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);
    }

    private static String relativePath() {
        return Environment.DIRECTORY_DOWNLOADS + "/" + DIR + "/";
    }
}
