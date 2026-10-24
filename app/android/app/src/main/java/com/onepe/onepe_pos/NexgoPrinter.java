package com.onepe.onepe_pos;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.Build;

import com.nexgo.oaf.apiv3.APIProxy;
import com.nexgo.oaf.apiv3.DeviceEngine;
import com.nexgo.oaf.apiv3.device.printer.AlignEnum;
import com.nexgo.oaf.apiv3.device.printer.GrayLevelEnum;
import com.nexgo.oaf.apiv3.device.printer.Printer;

import java.util.List;
import java.util.Locale;

/** Built-in printer of Nexgo terminals (N82 / N86), from the OnePe printer plugin's NexgoPrinterHelper. */
final class NexgoPrinter {
    interface Callback {
        void onResult(boolean success, String message);
    }

    private NexgoPrinter() {}

    static boolean isNexgo() {
        String id = (Build.MANUFACTURER + " " + Build.BRAND + " " + Build.MODEL).toLowerCase(Locale.ROOT);
        return id.contains("nexgo");
    }

    /** Prints the bitmaps (already 384 px wide) and recycles them when done. */
    static void print(Context context, List<Bitmap> pages, Callback callback) {
        try {
            DeviceEngine engine = APIProxy.getDeviceEngine(context.getApplicationContext());
            Printer printer = engine.getPrinter();
            int init = printer.initPrinter();
            if (init != 0) {
                PdfRaster.recycle(pages);
                callback.onResult(false, "Printer init failed (" + init + ")");
                return;
            }
            printer.setGray(GrayLevelEnum.LEVEL_1);
            for (Bitmap page : pages) printer.appendImage(page, AlignEnum.CENTER);
            printer.appendPrnStr("\n\n", 20, AlignEnum.CENTER, false);
            printer.startPrint(true, retCode -> {
                PdfRaster.recycle(pages);
                callback.onResult(retCode == 0, retCode == 0 ? null : errorText(retCode));
            });
        } catch (Throwable e) {
            PdfRaster.recycle(pages);
            callback.onResult(false, "In-device printer not available (" + e.getMessage() + ")");
        }
    }

    private static String errorText(int code) {
        switch (code) {
            case -1: return "Printer busy";
            case -2: return "Out of paper";
            case -3: return "Printer overheat";
            case -4: return "Low battery";
            default: return "Printer error code " + code;
        }
    }
}
