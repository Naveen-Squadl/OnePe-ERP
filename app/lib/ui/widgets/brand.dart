import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import 'common.dart';

/// OnePe logo from the brand assets. [lime] for blue/navy backgrounds, blue for light ones;
/// [iconOnly] shows just the "1" brand icon (UI / compact use per the brand guide).
class BrandLogo extends StatelessWidget {
  final double height;
  final bool lime;
  final bool iconOnly;
  const BrandLogo({super.key, this.height = 32, this.lime = false, this.iconOnly = false});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/brand/${iconOnly ? 'icon' : 'logo'}_${lime ? 'lime' : 'blue'}.png',
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'OnePe',
      );
}

/// OnePe Blue app bar with white title and rounded lower corners (used on every inner screen).
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
        backgroundColor: AppColors.blue,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(22))),
      );
}

/// Lime primary action with navy label ("Charge", "Add Product" ...). Name kept from the old theme.
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
        color: AppColors.lime,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: height,
            child: Center(
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (icon != null) ...[Icon(icon, color: AppColors.navy), const SizedBox(width: 10)],
                      Flexible(
                        child: Text(label,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined secondary action ("Apply Bill Discount").
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
          foregroundColor: AppColors.blue,
          side: const BorderSide(color: AppColors.blue, width: 1.4),
          minimumSize: const Size.fromHeight(48),
        ),
      );
}

/// Category filter: white rounded pill with a coloured dot; selected = solid OnePe Blue.
class CategoryChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const CategoryChip({super.key, required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.blue : Colors.white,
        shape: shape,
        elevation: selected ? 0 : 1,
        shadowColor: AppColors.navy.withValues(alpha: .15),
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 14, 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: selected ? AppColors.lime : color, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.navy, fontWeight: FontWeight.w700, fontSize: 13)),
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
  const CornerBadge(this.text, {super.key, this.color = const Color(0xE6183461)});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

/// Product photo, or the default placeholder on brand Cream.
class ProductImage extends StatelessWidget {
  final String? url;
  final double iconSize;
  final BorderRadius? radius;
  const ProductImage({super.key, this.url, this.iconSize = 26, this.radius});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.cream,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: const Color(0xFF8C8A5E), size: iconSize),
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
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: widget.size,
            height: widget.size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFD8D5A8))),
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
