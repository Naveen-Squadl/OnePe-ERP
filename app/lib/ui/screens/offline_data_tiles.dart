import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/customer_cache.dart';
import '../../services/local_store.dart';
import '../../services/offline_photos.dart';
import '../../services/offline_queue.dart';
import '../../state/catalog.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';

/// Settings → Offline Data & Backup: pending bills, backup folder, and what is stored on this device.
class OfflineDataTiles extends StatefulWidget {
  const OfflineDataTiles({super.key});
  @override
  State<OfflineDataTiles> createState() => _OfflineDataTilesState();
}

class _OfflineDataTilesState extends State<OfflineDataTiles> {
  int? _catalogBytes;
  int? _photoBytes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final sizes = await Future.wait([LocalStore.size(Catalog.filePrefix), OfflinePhotos.size(), LocalStore.size(CustomerCache.filePrefix)]);
    if (!mounted) return;
    setState(() {
      _catalogBytes = sizes[0] + sizes[2];
      _photoBytes = sizes[1];
    });
  }

  static String _size(int? bytes) => bytes == null
      ? '…'
      : bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(0)} KB'
          : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Select OnePe offline bill files');
    if (files.isEmpty || !mounted) return;
    final n = await guard(context, () async => OfflineQueue.import([for (final f in files) utf8.decode(await f.readAsBytes())]));
    if (n == null || !mounted) return;
    showSnack(context, '📥 $n bill(s) imported – uploading…');
    await syncCloudData(context);
  }

  Future<void> _clearPhotos() async {
    await OfflinePhotos.clear();
    await _measure();
    if (mounted) showSnack(context, 'Saved photos cleared – they download again when needed');
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<Catalog>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ValueListenableBuilder<int>(
        valueListenable: OfflineQueue.pending,
        builder: (_, pending, _) => ListTile(
          leading: Badge(
            isLabelVisible: pending > 0,
            backgroundColor: AppColors.amber,
            textColor: AppColors.navy,
            label: Text('$pending'),
            child: const Icon(Icons.sync),
          ),
          title: const Text('Sync Cloud Data'),
          subtitle: Text(pending > 0 ? '$pending offline bill(s) waiting to upload (retried automatically)' : 'Upload offline bills and refresh products'),
          onTap: () async {
            await syncCloudData(context);
            _measure();
          },
        ),
      ),
      if (OfflineQueue.hasBackupFolder)
        ValueListenableBuilder<String?>(
          valueListenable: OfflineQueue.folderAccess,
          builder: (_, folder, _) => ListTile(
            leading: Icon(folder == null ? Icons.folder_off_outlined : Icons.folder_special_outlined, color: folder == null ? AppColors.danger : null),
            title: const Text('Backup folder for offline bills'),
            subtitle: Text(folder == null
                ? 'Not set – choose ${OfflineQueue.backupFolder} so bills survive reinstall / clear data'
                : '$folder • recovered and cleaned up automatically'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => chooseBackupFolder(context),
          ),
        ),
      ListTile(
        leading: const Icon(Icons.restore_page_outlined),
        title: const Text('Import offline bills'),
        subtitle: const Text('Pick bill_….json backup files to upload them'),
        onTap: _import,
      ),
      const Divider(height: 1),
      ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: const Text('Saved products, prices & customers'),
        subtitle: Text('${catalog.products.length} products • ${_size(_catalogBytes)} on this device'
            '${catalog.savedAt != null ? ' • offline copy from ${dateTime(catalog.savedAt!)}' : ' • up to date'}'),
      ),
      if (OfflinePhotos.supported) ...[
        SwitchListTile(
          secondary: const Icon(Icons.photo_library_outlined),
          title: const Text('Keep product photos for offline'),
          subtitle: Text('Small thumbnails, max ${OfflinePhotos.maxPhotos} photos • ${_size(_photoBytes)} used'),
          value: OfflinePhotos.enabled,
          onChanged: (v) async {
            await OfflinePhotos.setEnabled(v);
            if (v) OfflinePhotos.prefetch(catalog.products.map((p) => p.imageUrl));
            await _measure();
          },
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Clear saved photos'),
          subtitle: const Text('Frees space; photos download again when online'),
          onTap: _clearPhotos,
        ),
      ],
    ]);
  }
}
