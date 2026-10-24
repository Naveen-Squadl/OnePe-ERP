package com.onepe.onepe_pos;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.pdf.PdfRenderer;
import android.os.ParcelFileDescriptor;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * Renders bill PDFs to bitmaps for raster printers (from the OnePe printer plugin's PdfToImageConverter):
 * each page is rendered at twice the target width, cropped to its printed content and scaled to the
 * printer width.
 */
final class PdfRaster {
    private static final int CONTENT_THRESHOLD = 245;
    private static final int CROP_PADDING = 10;
    private static final int MAX_RENDER_HEIGHT = 16000;

    private PdfRaster() {}

    static List<Bitmap> render(Context context, byte[] pdf, int targetWidth) throws IOException {
        if (pdf == null || pdf.length < 100) throw new IOException("PDF is empty or invalid");
        if (targetWidth <= 0) throw new IllegalArgumentException("Target width must be greater than zero");

        File file = File.createTempFile("bill_", ".pdf", context.getCacheDir());
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(pdf);
        }
        List<Bitmap> pages = new ArrayList<>();
        try (ParcelFileDescriptor fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
             PdfRenderer renderer = new PdfRenderer(fd)) {
            for (int i = 0; i < renderer.getPageCount(); i++) {
                try (PdfRenderer.Page page = renderer.openPage(i)) {
                    float scale = targetWidth * 2f / page.getWidth();
                    if (page.getHeight() * scale > MAX_RENDER_HEIGHT) scale = (float) MAX_RENDER_HEIGHT / page.getHeight();
                    int w = Math.max(1, Math.round(page.getWidth() * scale));
                    int h = Math.max(1, Math.round(page.getHeight() * scale));
                    Bitmap rendered = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                    rendered.eraseColor(Color.WHITE);
                    Matrix m = new Matrix();
                    m.setScale(scale, scale);
                    page.render(rendered, null, m, PdfRenderer.Page.RENDER_MODE_FOR_PRINT);
                    pages.add(cropAndScale(rendered, targetWidth));
                }
            }
        } finally {
            //noinspection ResultOfMethodCallIgnored
            file.delete();
        }
        return pages;
    }

    static List<byte[]> renderPng(Context context, byte[] pdf, int targetWidth) throws IOException {
        List<byte[]> out = new ArrayList<>();
        for (Bitmap bmp : render(context, pdf, targetWidth)) {
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            bmp.compress(Bitmap.CompressFormat.PNG, 100, buf);
            bmp.recycle();
            out.add(buf.toByteArray());
        }
        return out;
    }

    static void recycle(List<Bitmap> bitmaps) {
        for (Bitmap b : bitmaps) if (b != null && !b.isRecycled()) b.recycle();
    }

    private static Bitmap cropAndScale(Bitmap src, int targetWidth) {
        int w = src.getWidth(), h = src.getHeight();
        int[] px = new int[w * h];
        src.getPixels(px, 0, w, 0, 0, w, h);
        int left = w, right = -1, top = h, bottom = -1;
        for (int y = 0; y < h; y++) {
            int row = y * w;
            for (int x = 0; x < w; x++) {
                int p = px[row + x];
                if (Color.alpha(p) == 0) continue;
                if (Color.red(p) < CONTENT_THRESHOLD || Color.green(p) < CONTENT_THRESHOLD || Color.blue(p) < CONTENT_THRESHOLD) {
                    if (x < left) left = x;
                    if (x > right) right = x;
                    if (y < top) top = y;
                    if (y > bottom) bottom = y;
                }
            }
        }
        Bitmap cropped = src;
        if (left < right && top < bottom) {
            left = Math.max(0, left - CROP_PADDING);
            top = Math.max(0, top - CROP_PADDING);
            right = Math.min(w - 1, right + CROP_PADDING);
            bottom = Math.min(h - 1, bottom + CROP_PADDING);
            cropped = Bitmap.createBitmap(src, left, top, right - left + 1, bottom - top + 1);
        }
        int targetHeight = Math.max(1, Math.round((float) cropped.getHeight() * targetWidth / cropped.getWidth()));
        Bitmap scaled = Bitmap.createScaledBitmap(cropped, targetWidth, targetHeight, true);
        if (cropped != src && cropped != scaled) cropped.recycle();
        if (src != scaled) src.recycle();
        return scaled;
    }
}
