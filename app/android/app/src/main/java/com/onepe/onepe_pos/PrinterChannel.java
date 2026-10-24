package com.onepe.onepe_pos;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.Handler;
import android.os.Looper;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** "onepe/printer" method channel used by lib/services/device_printer.dart. */
final class PrinterChannel implements MethodChannel.MethodCallHandler {
    static final String NAME = "onepe/printer";

    private final Context context;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    PrinterChannel(Context context) {
        this.context = context.getApplicationContext();
    }

    static boolean needsBluetooth(String method) {
        return "pairedDevices".equals(method) || "printBluetooth".equals(method);
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "isNexgo":
                result.success(NexgoPrinter.isNexgo());
                return;
            case "printNexgo":
                worker.execute(() -> {
                    try {
                        List<Bitmap> pages = PdfRaster.render(context, call.argument("pdf"), intArg(call, "width", 384));
                        NexgoPrinter.print(context, pages, (ok, message) -> main.post(() -> {
                            if (ok) result.success("ok");
                            else result.error("PRINT_FAILED", message, null);
                        }));
                    } catch (Throwable e) {
                        fail(result, e);
                    }
                });
                return;
            case "printBluetooth":
                worker.execute(() -> {
                    try {
                        List<Bitmap> pages = PdfRaster.render(context, call.argument("pdf"), intArg(call, "width", 384));
                        BluetoothEscPos.print(call.argument("address"), pages);
                        main.post(() -> result.success("ok"));
                    } catch (Throwable e) {
                        fail(result, e);
                    }
                });
                return;
            case "pairedDevices":
                worker.execute(() -> {
                    try {
                        List<?> devices = BluetoothEscPos.pairedDevices();
                        main.post(() -> result.success(devices));
                    } catch (Throwable e) {
                        fail(result, e);
                    }
                });
                return;
            case "renderPdf":
                worker.execute(() -> {
                    try {
                        List<byte[]> pngs = PdfRaster.renderPng(context, call.argument("pdf"), intArg(call, "width", 384));
                        main.post(() -> result.success(pngs));
                    } catch (Throwable e) {
                        fail(result, e);
                    }
                });
                return;
            default:
                result.notImplemented();
        }
    }

    private static int intArg(MethodCall call, String key, int fallback) {
        Integer v = call.argument(key);
        return v == null ? fallback : v;
    }

    private void fail(MethodChannel.Result result, Throwable e) {
        String msg = e.getMessage() == null ? e.toString() : e.getMessage();
        main.post(() -> result.error("PRINT_FAILED", msg, null));
    }
}
