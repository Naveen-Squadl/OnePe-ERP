import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../services/offline_queue.dart';
import '../../../state/cart.dart';
import '../../../state/catalog.dart';
import '../../../state/session.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';
import '../../widgets/scanner.dart';
import '../reports/reports_screen.dart';
import 'cart_panel.dart';

/// Main billing screen: order details + product grid on the left, cart on the right.
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _search = TextEditingController();
  String? _categoryId;
  String _view = 'grid'; // grid | list
  bool _reportsMode = false;
  String? _branchLoaded;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _view = p.getString('pos_view_mode_pref') ?? 'grid');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => offerBackupFolder(context));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.watch<Session>();
    // Prices / stock are per outlet: reload when the active branch changes.
    if (s.activeBranchId != _branchLoaded) {
      _branchLoaded = s.activeBranchId;
      final cart = context.read<Cart>();
      cart.gstInclusive = s.shop?.settings.gstInclusive ?? false;
      WidgetsBinding.instance.addPostFrameCallback((_) => context.read<Catalog>().load());
    }
  }

  Future<void> _toggleView() async {
    setState(() => _view = _view == 'grid' ? 'list' : 'grid');
    (await SharedPreferences.getInstance()).setString('pos_view_mode_pref', _view);
  }

  Future<void> _addProduct(Product p) async {
    final cart = context.read<Cart>();
    try {
      if (p.isPriceVariable) {
        final price = await askNumber(context, 'Enter Price for ${p.name}', label: 'Price (₹)', initial: p.price);
        if (price == null) return;
        cart.add(p, price: price, priceType: 'custom');
      } else {
        cart.add(p);
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final p = context.read<Catalog>().byBarcode(code);
    if (p == null) return showSnack(context, 'No matching product found for code: $code', error: true);
    if (!p.availableHere) return showSnack(context, '⚠️ ${p.name} is not available in current branch', error: true);
    await _addProduct(p);
    if (mounted) showSnack(context, '⚡ Added ${p.name} to rapid bill!');
  }

  Future<void> _openWaitingList() async {
    final bill = await showModalBottomSheet<Bill>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const _WaitingListSheet());
    if (bill == null || !mounted) return;
    Customer? c;
    if (bill.customerId != null) c = Customer(Map<String, dynamic>.from(await Api.instance.get('/customers/${bill.customerId}')));
    if (!mounted) return;
    context.read<Cart>().loadBill(bill, customerObj: c);
    showSnack(context, 'Loaded waiting bill ${bill.tableName ?? '#${bill.billNo}'}');
  }

  void _openCartPage() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.bg,
          body: CartPanel(popOnDone: true),
        ),
      ));

  /// Bottom bar / side menu destinations (filtered by permission).
  List<_NavDest> _destinations(Session session, {required bool wide}) => [
        _NavDest('Sell', Icons.grid_view_rounded, () => setState(() => _reportsMode = false), selected: !_reportsMode),
        if (session.can('bills.view')) _NavDest('Bills', Icons.receipt_long_rounded, () => context.go('/bills')),
        if (session.can('reports.view')) _NavDest('Reports', Icons.bar_chart_rounded, () => setState(() => _reportsMode = true), selected: _reportsMode),
        if (wide && session.can('customers.manage')) _NavDest('Customers', Icons.people_alt_rounded, () => context.go('/customers')),
        if (wide && session.can('inventory.view')) _NavDest('Stock', Icons.inventory_2_rounded, () => context.go('/stock')),
        if (wide && session.can('settings.manage')) _NavDest('Settings', Icons.tune_rounded, () => context.go('/settings')),
      ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final cart = context.watch<Cart>();
    final session = context.watch<Session>();
    final header = _PosHeader(
      wide: wide,
      onSync: () => syncCloudData(context),
      onWaiting: _openWaitingList,
      search: wide ? _searchField() : null,
    );
    if (wide) {
      return Scaffold(
        drawer: const AppDrawer(),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Builder(builder: (c) => _SideRail(items: _destinations(session, wide: true), onMore: () => Scaffold.of(c).openDrawer())),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  header,
                  const SizedBox(height: 6),
                  Expanded(child: _reportsMode ? const ReportsView(embedded: true) : _productArea(wide)),
                ]),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 372,
                child: ClipRRect(borderRadius: BorderRadius.circular(26), child: CartPanel()),
              ),
            ]),
          ),
        ),
      );
    }
    return Scaffold(
      drawer: const AppDrawer(),
      body: Stack(children: [
        Column(children: [
          header,
          Expanded(
            child: _reportsMode
                ? const Padding(padding: EdgeInsets.only(bottom: 84), child: ReportsView(embedded: true))
                : Column(children: [
                    Transform.translate(offset: const Offset(0, -30), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _searchField())),
                    Expanded(child: Transform.translate(offset: const Offset(0, -22), child: _productArea(wide))),
                  ]),
          ),
        ]),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: Builder(
              builder: (c) => _Dock(
                items: _destinations(session, wide: false),
                onMore: () => Scaffold.of(c).openDrawer(),
                cartCount: cart.itemCount,
                cartTotal: cart.payable,
                onCart: _openCartPage,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// White search pill with list/grid toggle and the Scan button.
  Widget _searchField() {
    final catalog = context.read<Catalog>();
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: AppColors.navy.withValues(alpha: .25),
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 52,
        child: Row(children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                filled: false,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search items or scan',
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (v) {
                final p = catalog.byBarcode(v);
                if (p != null) {
                  _addProduct(p);
                  _search.clear();
                  setState(() {});
                }
              },
            ),
          ),
          IconButton(
            tooltip: _view == 'grid' ? 'List view' : 'Grid view',
            onPressed: _toggleView,
            icon: Icon(_view == 'grid' ? Icons.view_list_rounded : Icons.grid_view_rounded, color: AppColors.muted),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconButton.filled(
              tooltip: 'Scan QR / Barcode for Rapid Bill',
              onPressed: _scan,
              style: IconButton.styleFrom(backgroundColor: AppColors.blue, foregroundColor: Colors.white, fixedSize: const Size(40, 40)),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _productArea(bool wide) {
    final catalog = context.watch<Catalog>();
    // Expense categories show up at the end of the chip row; picking one switches to expense items.
    final cats = catalog.categories;
    final selectedCat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final expense = selectedCat?.isExpenseCategory ?? false;
    final products = catalog.filter(categoryId: _categoryId, query: _search.text, expense: expense);
    final hPad = wide ? 4.0 : 16.0;
    return Column(children: [
      SizedBox(
        height: 54,
        child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 8), children: [
          CategoryChip(label: 'All', color: AppColors.lime, selected: _categoryId == null, onTap: () => setState(() => _categoryId = null)),
          for (final (i, c) in cats.indexed)
            CategoryChip(
              label: c.isExpenseCategory ? '${c.name} (Expense)' : c.name,
              color: c.isExpenseCategory ? AppColors.amber : AppColors.forIndex(i),
              selected: _categoryId == c.id,
              onTap: () => setState(() => _categoryId = c.id),
            ),
        ]),
      ),
      if (catalog.savedAt != null)
        Padding(
          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
          child: Material(
            color: AppColors.amber.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: catalog.load,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Offline – products & prices saved ${dateTime(catalog.savedAt!)}. Bills sync when back online.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
                  ),
                  const Icon(Icons.refresh_rounded, size: 18, color: AppColors.navy),
                ]),
              ),
            ),
          ),
        ),
      Expanded(
        child: catalog.loading && catalog.products.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : catalog.error != null && catalog.products.isEmpty
                ? ErrorView(message: catalog.error!, onRetry: catalog.load)
                : products.isEmpty
                    ? const EmptyState(icon: Icons.search_off, title: 'No products found')
                    : RefreshIndicator(
                        onRefresh: catalog.load,
                        child: _view == 'list' ? _list(products, cats, hPad, wide) : _grid(products, cats, hPad, wide),
                      ),
      ),
    ]);
  }

  Widget _grid(List<Product> products, List<Category> cats, double hPad, bool wide) => LayoutBuilder(builder: (context, box) {
        final cols = (box.maxWidth / (wide ? 210 : 170)).floor().clamp(2, 8);
        final imageH = wide ? 112.0 : 88.0;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(hPad, 4, hPad, wide ? 16 : 100),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: imageH + 104),
          itemCount: products.length,
          itemBuilder: (_, i) => _ProductCard(product: products[i], imageHeight: imageH, onAdd: () => _addProduct(products[i])),
        );
      });

  Widget _list(List<Product> products, List<Category> cats, double hPad, bool wide) => ListView.separated(
        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, wide ? 16 : 100),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = products[i];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              leading: SizedBox(width: 52, height: 52, child: ProductImage(url: p.imageUrl, radius: BorderRadius.circular(14), iconSize: 20)),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Row(children: [
                Text(money(p.price), style: const TextStyle(color: AppColors.price, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                if (p.trackStock && !p.isExpense) _StockText(p),
              ]),
              trailing: _AddOrStepper(product: p, onAdd: () => _addProduct(p)),
            ),
          );
        },
      );
}

class _StockText extends StatelessWidget {
  final Product p;
  const _StockText(this.p);
  @override
  Widget build(BuildContext context) => Text(
        'Stock: ${qty(p.stock)}',
        style: TextStyle(fontSize: 11, color: p.stock <= 0 || p.isLowStock ? AppColors.danger : AppColors.muted, fontWeight: FontWeight.w500),
      );
}

/// Lime "+" button, or a blue − qty + stepper when the item is already in the cart.
class _AddOrStepper extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;
  const _AddOrStepper({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final line = cart.lines.where((l) => l.productId == product.id).firstOrNull;
    if (line == null) {
      return IconButton.filled(
        tooltip: 'Add to cart',
        onPressed: onAdd,
        style: IconButton.styleFrom(backgroundColor: AppColors.lime, foregroundColor: AppColors.navy, fixedSize: const Size(38, 38), minimumSize: const Size(38, 38)),
        icon: const Icon(Icons.add_rounded, size: 22),
      );
    }
    return Container(
      height: 38,
      decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _stepBtn(Icons.remove_rounded, 'Remove one', () => cart.setQty(line, line.quantity - 1)),
        InkWell(
          onTap: () async {
            final v = await askNumber(context, 'Set Quantity (${line.name})', label: 'Quantity', initial: line.quantity);
            if (v != null) cart.setQty(line, v);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 18),
            child: Text(qty(line.quantity), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.lime, fontSize: 14)),
          ),
        ),
        _stepBtn(Icons.add_rounded, 'Add one more', () => cart.setQty(line, line.quantity + 1)),
      ]),
    );
  }

  Widget _stepBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 32, height: 38, child: Icon(icon, size: 18, color: Colors.white)),
        ),
      );
}

/// Stock pill on the product photo: "48 in stock", amber "Only 6 left", coral "Out of stock".
class _StockBadge extends StatelessWidget {
  final Product p;
  const _StockBadge(this.p);

  @override
  Widget build(BuildContext context) {
    final out = p.stock <= 0;
    final low = !out && p.isLowStock;
    final (bg, fg, label) = out
        ? (AppColors.danger, Colors.white, 'Out of stock')
        : low
            ? (AppColors.amber, AppColors.navy, 'Only ${qty(p.stock)} left')
            : (Colors.white.withValues(alpha: .92), AppColors.navy, '${qty(p.stock)} in stock');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final double imageHeight;
  final VoidCallback onAdd;
  const _ProductCard({required this.product, required this.imageHeight, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final inCart = context.select<Cart, bool>((cart) => cart.lines.any((l) => l.productId == p.id));
    return Material(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: AppColors.navy.withValues(alpha: .14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: inCart ? const BorderSide(color: AppColors.blue, width: 1.6) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: imageHeight,
              child: Stack(fit: StackFit.expand, children: [
                ProductImage(url: p.imageUrl, radius: BorderRadius.circular(17)),
                if (p.trackStock && !p.isExpense) Positioned(left: 6, top: 6, child: _StockBadge(p)),
              ]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                height: 36,
                child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.35)),
              ),
            ),
            const Spacer(),
            Row(children: [
              const SizedBox(width: 6),
              Expanded(
                child: Text(money(p.price).replaceAll('.00', ''),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.price, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.3)),
              ),
              _AddOrStepper(product: p, onAdd: onAdd),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _WaitingListSheet extends StatelessWidget {
  const _WaitingListSheet();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * .75,
        child: Column(children: [
          const ListTile(title: Text('Waiting List', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)), subtitle: Text('Active orders will appear here')),
          Expanded(
            child: Loader<List<Bill>>(
              load: () async => (await Api.instance.get('/bills', {'status': 'waiting'}) as List).map((e) => Bill(Map<String, dynamic>.from(e))).toList(),
              builder: (context, bills, _) => bills.isEmpty
                  ? ListView(children: const [SizedBox(height: 80), EmptyState(icon: Icons.inbox, title: 'No waiting list bills')])
                  : ListView(children: [
                      for (final b in bills)
                        ListTile(
                          leading: CircleAvatar(backgroundColor: AppColors.amber, child: Text(b.tableName?.characters.first ?? '#', style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800))),
                          title: Text('${b.tableName ?? 'Order'} • #${b.billNo.split('-').last}'),
                          subtitle: Text('${b.items.length} items • ${dateTime(b.billDate)}${b.customerName != null ? ' • ${b.customerName}' : ''}'),
                          trailing: Text(money(b.total), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.blue)),
                          onTap: () => Navigator.pop(context, b),
                        ),
                    ]),
            ),
          ),
        ]),
      );
}

class _NavDest {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  const _NavDest(this.label, this.icon, this.onTap, {this.selected = false});
}

/// OnePe Blue POS header on the brand's lime stepped edge. Phone: logo, branch, sync, profile and
/// the order row (customer / table / new order). Wide: logo-less title row with search and Waiting.
class _PosHeader extends StatelessWidget {
  final bool wide;
  final VoidCallback onSync;
  final VoidCallback onWaiting;
  final Widget? search;
  const _PosHeader({required this.wide, required this.onSync, required this.onWaiting, this.search});

  static ButtonStyle _glass([double? w]) => IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .14),
        foregroundColor: Colors.white,
        fixedSize: Size(w ?? 44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final cart = context.watch<Cart>();
    final canSwitch = session.branches.length > 1 && (session.user?.isAdminOrManager ?? false);
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(session.shop?.name ?? 'OnePe ERP',
          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: wide ? 21 : 17, letterSpacing: -0.3)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(session.activeBranch?.name ?? 'Main Branch',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.lime, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        if (canSwitch) const Icon(Icons.expand_more_rounded, color: AppColors.lime, size: 16),
      ]),
    ]);
    final branch = canSwitch
        ? PopupMenuButton<String>(
            tooltip: 'Switch outlet',
            onSelected: session.switchBranch,
            itemBuilder: (_) => [for (final b in session.branches) CheckedPopupMenuItem(value: b.id, checked: b.id == session.activeBranchId, child: Text(b.name))],
            child: title,
          )
        : title;
    final sync = ValueListenableBuilder<int>(
      valueListenable: OfflineQueue.pending,
      builder: (_, pending, _) => IconButton(
        tooltip: pending > 0 ? 'Sync $pending offline bill(s)' : 'Sync Cloud Data',
        onPressed: onSync,
        style: _glass(),
        icon: Badge(
          isLabelVisible: pending > 0,
          backgroundColor: AppColors.amber,
          textColor: AppColors.navy,
          label: Text('$pending'),
          child: const Icon(Icons.sync_rounded, size: 21),
        ),
      ),
    );
    final profile = PopupMenuButton<String>(
      tooltip: 'Profile',
      onSelected: (v) => v == 'logout' ? safeLogout(context) : null,
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text('${session.user?.name}\n${session.user?.role.replaceAll('_', ' ')}')),
        const PopupMenuItem(value: 'logout', child: Text('Logout')),
      ],
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(14)),
        child: Text(initials(session.user?.name), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 13)),
      ),
    );

    if (wide) {
      return _LimeStep(
        radius: 26,
        child: Container(
          height: 84,
          padding: const EdgeInsets.fromLTRB(22, 0, 14, 0),
          decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(26)),
          child: Row(children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: branch)),
            const SizedBox(width: 16),
            Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: search)),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: onWaiting,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: .14),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.pending_actions_rounded, size: 18),
              label: const Text('Waiting'),
            ),
            const SizedBox(width: 8),
            sync,
            const SizedBox(width: 8),
            profile,
          ]),
        ),
      );
    }

    final customerName = cart.customer?.name ?? (cart.customerPhone?.length == 10 ? (cart.customerName ?? cart.customerPhone!) : 'Walk-in');
    return _LimeStep(
      radius: 28,
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(10, MediaQuery.of(context).padding.top + 6, 12, 42),
        decoration: const BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.vertical(bottom: Radius.circular(28))),
        child: Column(children: [
          SizedBox(
            height: 48,
            child: Row(children: [
              const BrandLogo(height: 40, lime: true, iconOnly: true),
              const SizedBox(width: 4),
              Expanded(child: branch),
              sync,
              const SizedBox(width: 6),
              profile,
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Material(
                color: Colors.white.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final c = await pickCustomer(context);
                    if (c != null) cart.setCustomer(c);
                  },
                  child: SizedBox(
                    height: 44,
                    child: Row(children: [
                      const SizedBox(width: 10),
                      const Icon(Icons.person_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(customerName,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      Container(
                        height: 30,
                        margin: const EdgeInsets.only(right: 7),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(10)),
                        child: Text(cart.hasCustomer ? 'Change' : 'Search / Add',
                            style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => pickTable(context, cart),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: .14),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.table_restaurant_rounded, size: 18),
              label: Text(cart.tableName ?? 'Table', style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'New Order',
              onPressed: () {
                cart.clear();
                showSnack(context, 'New order started.');
              },
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.blue,
                fixedSize: const Size(44, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add_rounded, size: 24),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Brand element: a lime strip stepping out from under a blue panel's lower-left edge.
class _LimeStep extends StatelessWidget {
  final Widget child;
  final double radius;
  final bool top;
  const _LimeStep({required this.child, required this.radius, this.top = true});

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned(
          left: 0,
          bottom: 0,
          width: MediaQuery.of(context).size.width * (top ? .28 : .62),
          height: 56,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.lime,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(top ? radius : 0), bottomRight: Radius.circular(radius)),
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.only(bottom: 7), child: child),
      ]);
}

/// Navy side menu (web / tablet) with the lime OnePe icon.
class _SideRail extends StatelessWidget {
  final List<_NavDest> items;
  final VoidCallback onMore;
  const _SideRail({required this.items, required this.onMore});

  Widget _item(_NavDest d) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: d.selected ? AppColors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: d.onTap,
            child: SizedBox(
              width: 68,
              height: 62,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(d.icon, color: d.selected ? AppColors.lime : const Color(0xFFB9C4D8), size: 23),
                const SizedBox(height: 4),
                Text(d.label, style: TextStyle(color: d.selected ? Colors.white : const Color(0xFFB9C4D8), fontSize: 11, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        width: 86,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(26)),
        child: Column(children: [
          const BrandLogo(height: 60, lime: true, iconOnly: true),
          const SizedBox(height: 10),
          Expanded(child: SingleChildScrollView(child: Column(children: [for (final d in items) _item(d)]))),
          _item(_NavDest('More', Icons.menu_rounded, onMore)),
        ]),
      );
}

/// Floating navy bottom bar (phone): Sell · Bills · Reports · More, plus the lime cart button.
class _Dock extends StatelessWidget {
  final List<_NavDest> items;
  final VoidCallback onMore;
  final double cartCount;
  final double cartTotal;
  final VoidCallback onCart;
  const _Dock({required this.items, required this.onMore, required this.cartCount, required this.cartTotal, required this.onCart});

  Widget _icon(_NavDest d) => Tooltip(
        message: d.label,
        child: Material(
          color: d.selected ? AppColors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: d.onTap,
            child: SizedBox(width: 46, height: 46, child: Icon(d.icon, color: d.selected ? AppColors.lime : const Color(0xFFB9C4D8), size: 23)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: .35), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Row(children: [
          for (final d in items) _icon(d),
          _icon(_NavDest('More', Icons.more_horiz_rounded, onMore)),
          const Spacer(),
          Material(
            color: AppColors.lime,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onCart,
              child: Container(
                height: 48,
                padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
                child: Row(children: [
                  Container(
                    constraints: const BoxConstraints(minWidth: 30),
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(10)),
                    child: Text(qty(cartCount), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  Text(money(cartTotal).replaceAll('.00', ''), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: -0.3)),
                ]),
              ),
            ),
          ),
        ]),
      );
}
