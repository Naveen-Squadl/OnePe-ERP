import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import 'common.dart';

/// Blue gradient app bar with white, centred title (used on every screen).
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  const GradientAppBar({super.key, this.title, this.leading, this.actions = const [], this.bottom, this.centerTitle = true});

  @override
  Size get preferredSize => Size.fromHeight(56 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) => AppBar(
        title: title,
        leading: leading,
        centerTitle: centerTitle,
        actions: actions,
        bottom: bottom,
        automaticallyImplyLeading: leading == null,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppColors.headerGradient)),
      );
}

/// Green gradient primary action ("Proceed to Payment", "Add Product" ...).
class GreenButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final bool busy;
  const GreenButton({super.key, required this.label, this.icon, this.onPressed, this.height = 56, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: Material(
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        elevation: enabled ? 3 : 0,
        shadowColor: AppColors.green.withValues(alpha: .4),
        child: Ink(
          height: height,
          decoration: const BoxDecoration(gradient: AppColors.greenGradient),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Center(
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, color: Colors.white), const SizedBox(width: 10)],
                      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined green action ("Apply Bill Discount").
class GreenOutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const GreenOutlineButton({super.key, required this.label, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.green,
          side: const BorderSide(color: AppColors.green, width: 1.2),
          minimumSize: const Size.fromHeight(50),
        ),
      );
}

/// Pill-shaped category filter with a coloured dot.
class CategoryChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const CategoryChip({super.key, required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppColors.blue : color.withValues(alpha: .10);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.blue : color.withValues(alpha: .45))),
        elevation: selected ? 3 : 0,
        shadowColor: AppColors.blue.withValues(alpha: .4),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: selected ? Colors.white : color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.text, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Small dark badge shown on product image corners.
class CornerBadge extends StatelessWidget {
  final String text;
  final Color color;
  const CornerBadge(this.text, {super.key, this.color = const Color(0xCC5F6368)});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

/// Product photo, or the default bag placeholder on a soft gradient.
class ProductImage extends StatelessWidget {
  final String? url;
  final double iconSize;
  final BorderRadius? radius;
  const ProductImage({super.key, this.url, this.iconSize = 26, this.radius});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF1F3F7), Color(0xFFE2E7F0)])),
      alignment: Alignment.center,
      child: Icon(Icons.shopping_bag, color: AppColors.blue.withValues(alpha: .75), size: iconSize),
    );
    final full = Api.mediaUrl(url);
    final child = full == null
        ? placeholder
        : Image.network(full, fit: BoxFit.cover, width: double.infinity, height: double.infinity, errorBuilder: (_, _, _) => placeholder);
    return radius == null ? child : ClipRRect(borderRadius: radius!, child: child);
  }
}

/// Coloured rounded-square icon used in lists and the drawer.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconTile(this.icon, this.color, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(size * .28)),
        child: Icon(icon, color: color, size: size * .55),
      );
}

/// Tiny coloured action icon button (edit / delete / print in list rows).
class RowAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const RowAction(this.icon, this.color, this.tooltip, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 22),
        style: IconButton.styleFrom(backgroundColor: color.withValues(alpha: .08)),
      );
}

/// "Add photo" box: picks from camera/gallery, uploads, and reports the stored URL.
class PhotoPickerBox extends StatefulWidget {
  final String? url;
  final ValueChanged<String?> onChanged;
  final String label;
  final double size;
  const PhotoPickerBox({super.key, required this.url, required this.onChanged, this.label = 'Add Photo', this.size = 110});

  @override
  State<PhotoPickerBox> createState() => _PhotoPickerBoxState();
}

class _PhotoPickerBoxState extends State<PhotoPickerBox> {
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 82);
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    final url = await guard(context, () async => Api.instance.uploadImage(await file.readAsBytes(), file.name));
    if (mounted) setState(() => _busy = false);
    if (url != null) widget.onChanged(url);
  }

  Future<void> _menu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take Photo'), onTap: () => Navigator.pop(c, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from Gallery / Files'), onTap: () => Navigator.pop(c, 'gallery')),
          if (widget.url != null)
            ListTile(leading: const Icon(Icons.delete_outline, color: AppColors.danger), title: const Text('Remove Photo'), onTap: () => Navigator.pop(c, 'remove')),
        ]),
      ),
    );
    switch (choice) {
      case 'camera':
        await _pick(ImageSource.camera);
      case 'gallery':
        await _pick(ImageSource.gallery);
      case 'remove':
        widget.onChanged(null);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: InkWell(
          onTap: _busy ? null : _menu,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: widget.size,
            height: widget.size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: const Color(0xFFE6E8EC), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF9AA0AA))),
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : widget.url != null
                    ? Stack(fit: StackFit.expand, children: [
                        ProductImage(url: widget.url),
                        const Positioned(right: 6, bottom: 6, child: CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.edit, size: 16))),
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.add_a_photo_outlined, size: 38, color: AppColors.muted),
                        const SizedBox(height: 6),
                        Text(widget.label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ]),
          ),
        ),
      );
}
