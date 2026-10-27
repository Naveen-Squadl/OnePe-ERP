import 'package:flutter/material.dart';

import '../../core/api.dart';

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
}

/// Runs [action], shows errors as a snackbar. Returns null on failure.
Future<T?> guard<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final r = await action();
    if (success != null && context.mounted) showSnack(context, success);
    return r;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) showSnack(context, e.toString(), error: true);
  }
  return null;
}

Future<bool> confirm(BuildContext context, String title, String message, {String ok = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: c.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: c.outline), textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.all(8), child: Text(message, textAlign: TextAlign.center)),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      );
}

/// Loads data with [load] and renders it with [builder]; handles loading / error / refresh.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;
  const Loader({super.key, required this.load, required this.builder});

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  T? data;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(covariant Loader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load) reload();
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await widget.load();
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading && data == null) return const Center(child: CircularProgressIndicator());
    if (error != null && data == null) return ErrorView(message: error!, onRetry: reload);
    return RefreshIndicator(onRefresh: reload, child: widget.builder(context, data as T, reload));
  }
}

class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final Widget? suffix;
  const SearchField({super.key, required this.hint, required this.onChanged, this.controller, this.suffix});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: hint, suffixIcon: suffix, isDense: true),
      );
}

/// Small coloured pill (status labels).
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const StatTile({super.key, required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(backgroundColor: c.withValues(alpha: .12), child: Icon(icon, color: c)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Labelled number input used in many dialogs.
Future<double?> askNumber(BuildContext context, String title, {String label = 'Amount', double? initial}) async {
  final ctrl = TextEditingController(text: initial == null ? '' : initial.toString());
  return showDialog<double>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(c, double.tryParse(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(ctrl.text)), child: const Text('OK')),
      ],
    ),
  );
}
