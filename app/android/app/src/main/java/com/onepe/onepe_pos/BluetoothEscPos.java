package com.onepe.onepe_pos;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.graphics.Bitmap;
import android.graphics.Color;

import java.io.IOException;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Bluetooth (SPP) ESC/POS printers: bills are sent as raster images (GS v 0) at the paper's dot width. */
@SuppressLint("MissingPermission") // BLUETOOTH_CONNECT is requested by MainActivity before any call.
final class BluetoothEscPos {
    private static final UUID SPP = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
    private static final int BAND_ROWS = 128;

    private BluetoothEscPos() {}

    private static BluetoothAdapter adapter() throws IOException {
        BluetoothAdapter a = BluetoothAdapter.getDefaultAdapter();
        if (a == null) throw new IOException("This device has no Bluetooth");
        if (!a.isEnabled()) throw new IOException("Turn on Bluetooth to print");
        return a;
    }

    static List<Map<String, String>> pairedDevices() throws IOException {
        List<Map<String, String>> out = new ArrayList<>();
        for (BluetoothDevice d : adapter().getBondedDevices()) {
            Map<String, String> m = new HashMap<>();
            m.put("name", d.getName() == null ? d.getAddress() : d.getName());
            m.put("address", d.getAddress());
            out.add(m);
        }
        return out;
    }

    static void print(String address, List<Bitmap> pages) throws IOException {
        BluetoothAdapter a = adapter();
        a.cancelDiscovery();
        BluetoothDevice device = a.getRemoteDevice(address);
        BluetoothSocket socket = device.createRfcommSocketToServiceRecord(SPP);
        try {
            try {
                socket.connect();
            } catch (IOException secureFailed) {
                socket.close();
                socket = device.createInsecureRfcommSocketToServiceRecord(SPP);
                socket.connect();
            }
            OutputStream out = socket.getOutputStream();
            long sent = 0;
            out.write(new byte[]{0x1B, 0x40}); // ESC @ – initialise
            for (Bitmap page : pages) sent += writeRaster(out, page);
            out.write(new byte[]{0x1B, 0x64, 0x04}); // feed 4 lines
            out.write(new byte[]{0x1D, 0x56, 0x42, 0x00}); // partial cut (ignored without a cutter)
            out.flush();
            // Let the printer drain its buffer before the link drops.
            try {
                Thread.sleep(Math.min(6000, 400 + sent / 25));
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
        } catch (IOException e) {
            throw new IOException("Could not print on " + address + ": " + e.getMessage(), e);
        } finally {
            try {
                socket.close();
            } catch (IOException ignored) {
            }
            PdfRaster.recycle(pages);
        }
    }

    /** GS v 0 raster bands; dark pixels (luminance < 160) print black. Returns bytes written. */
    private static long writeRaster(OutputStream out, Bitmap bmp) throws IOException {
        int w = bmp.getWidth(), h = bmp.getHeight();
        int bytesPerRow = (w + 7) / 8;
        int[] row = new int[w];
        long total = 0;
        for (int y0 = 0; y0 < h; y0 += BAND_ROWS) {
            int rows = Math.min(BAND_ROWS, h - y0);
            byte[] band = new byte[8 + bytesPerRow * rows];
            band[0] = 0x1D; band[1] = 0x76; band[2] = 0x30; band[3] = 0x00;
            band[4] = (byte) (bytesPerRow & 0xFF); band[5] = (byte) ((bytesPerRow >> 8) & 0xFF);
            band[6] = (byte) (rows & 0xFF); band[7] = (byte) ((rows >> 8) & 0xFF);
            for (int r = 0; r < rows; r++) {
                bmp.getPixels(row, 0, w, 0, y0 + r, w, 1);
                int base = 8 + r * bytesPerRow;
                for (int x = 0; x < w; x++) {
                    int p = row[x];
                    if (Color.alpha(p) < 128) continue;
                    int lum = (Color.red(p) * 299 + Color.green(p) * 587 + Color.blue(p) * 114) / 1000;
                    if (lum < 160) band[base + (x >> 3)] |= (byte) (0x80 >> (x & 7));
                }
            }
            out.write(band);
            total += band.length;
        }
        return total;
    }
}
