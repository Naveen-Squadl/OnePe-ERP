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
  bool _detailsOpen = false;
  int _pending = 0;
  String? _branchLoaded;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _view = p.getString('pos_view_mode_pref') ?? 'grid');
    });
    _refreshPending();
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
      cart.defaultPriceOption = s.shop?.settings.defaultPriceOption ?? 'base';
      WidgetsBinding.instance.addPostFrameCallback((_) => context.read<Catalog>().load());
    }
  }

  Future<void> _refreshPending() async {
    final n = (await OfflineQueue.all()).length;
    if (mounted) setState(() => _pending = n);
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
          appBar: const GradientAppBar(title: Text('Your Cart')),
          body: CartPanel(onCheckedOut: _refreshPending, popOnDone: true),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final cart = context.watch<Cart>();
    final session = context.watch<Session>();
    final canReports = session.can('reports.view');
    return Scaffold(
      drawer: const AppDrawer(),
      endDrawer: const AppDrawer(),
      appBar: GradientAppBar(
        centerTitle: false,
        leading: Builder(builder: (c) => IconButton(tooltip: 'Open navigation menu', icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(c).openDrawer())),
        title: Row(children: [
          const Icon(Icons.storefront_rounded),
          if (session.branches.length > 1) ...[const SizedBox(width: 8), const BranchSwitcher()],
        ]),
        actions: [
          if (canReports)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: .18),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () => setState(() => _reportsMode = !_reportsMode),
                icon: Icon(_reportsMode ? Icons.storefront : Icons.bar_chart, size: 18),
                label: Text(_reportsMode ? 'Shop ⇄' : 'Reports ⇄', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          IconButton(
            tooltip: 'New Order',
            onPressed: () {
              cart.clear();
              showSnack(context, 'New order started.');
            },
            icon: const Icon(Icons.add_shopping_cart),
          ),
          if (session.can('bills.view')) IconButton(tooltip: 'Bills History', onPressed: () => context.go('/bills'), icon: const Icon(Icons.playlist_add_check)),
          PopupMenuButton<String>(
            tooltip: 'Profile',
            icon: const CircleAvatar(radius: 14, backgroundColor: Colors.white30, child: Icon(Icons.person, size: 18, color: Colors.white)),
            onSelected: (v) => v == 'logout' ? session.logout() : null,
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text('${session.user?.name}\n${session.user?.role.replaceAll('_', ' ')}')),
              const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
          IconButton(
            tooltip: _pending > 0 ? 'Sync $_pending offline bill(s)' : 'Sync Cloud Data',
            onPressed: () async {
              await syncCloudData(context);
              _refreshPending();
            },
            icon: Badge(isLabelVisible: _pending > 0, label: Text('$_pending'), child: const Icon(Icons.sync)),
          ),
          IconButton(
            tooltip: wide ? 'Waiting List' : 'Your Cart',
            onPressed: wide ? _openWaitingList : _openCartPage,
            icon: Badge(isLabelVisible: !wide && !cart.isEmpty, label: Text(qty(cart.itemCount)), child: const Icon(Icons.shopping_cart)),
          ),
          Builder(builder: (c) => IconButton(tooltip: 'Menu', icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(c).openEndDrawer())),
        ],
      ),
      body: Row(children: [
        Expanded(child: _reportsMode ? const ReportsView(embedded: true) : _productArea(wide)),
        if (wide) Container(width: 360, decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.border))), child: CartPanel(onCheckedOut: _refreshPending)),
      ]),
      bottomNavigationBar: wide || cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: GreenButton(label: '${qty(cart.itemCount)} item(s) • ${money(cart.total)}  —  View Cart', icon: Icons.shopping_cart, onPressed: _openCartPage, height: 52),
              ),
            ),
    );
  }

  Widget _productArea(bool wide) {
    final catalog = context.watch<Catalog>();
    final cart = context.watch<Cart>();
    // Expense categories show up at the end of the chip row; picking one switches to expense items.
    final cats = catalog.categories;
    final selectedCat = cats.where((c) => c.id == _categoryId).firstOrNull;
    final expense = selectedCat?.isExpenseCategory ?? false;
    final products = catalog.filter(categoryId: _categoryId, query: _search.text, expense: expense);
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 0), child: _OrderDetailsCard(open: _detailsOpen, onToggle: () => setState(() => _detailsOpen = !_detailsOpen), cart: cart)),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              prefixIcon: const Icon(Icons.search, color: AppColors.blue),
              hintText: 'Search items or scan barcode...',
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: _view == 'grid' ? 'List view' : 'Grid view', onPressed: _toggleView, icon: Icon(_view == 'grid' ? Icons.grid_view_rounded : Icons.view_list_rounded, color: AppColors.blue)),
                IconButton(tooltip: 'Scan QR / Barcode for Rapid Bill', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner, color: AppColors.blue)),
              ]),
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
      ),
      SizedBox(
        height: 58,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), children: [
          CategoryChip(label: 'All', color: AppColors.blue, selected: _categoryId == null, onTap: () => setState(() => _categoryId = null)),
          for (final (i, c) in cats.indexed)
            CategoryChip(
              label: c.isExpenseCategory ? '${c.name} (Expense)' : c.name,
              color: c.isExpenseCategory ? AppColors.orange : AppColors.forIndex(i),
              selected: _categoryId == c.id,
              onTap: () => setState(() => _categoryId = c.id),
            ),
        ]),
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
                        child: _view == 'list' ? _list(products, cats) : _grid(products, cats),
                      ),
      ),
    ]);
  }

  Widget _grid(List<Product> products, List<Category> cats) => LayoutBuilder(builder: (context, box) {
        final cols = (box.maxWidth / 215).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 252),
          itemCount: products.length,
          itemBuilder: (_, i) => _ProductCard(product: products[i], onAdd: () => _addProduct(products[i])),
        );
      });

  Widget _list(List<Product> products, List<Category> cats) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = products[i];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              leading: SizedBox(width: 52, height: 52, child: ProductImage(url: p.imageUrl, radius: BorderRadius.circular(10), iconSize: 20)),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Row(children: [
                Text(money(p.price), style: const TextStyle(color: AppColors.price, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                if (p.trackStock && !p.isExpense) _StockText(p),
              ]),
              trailing: SizedBox(width: 150, child: _AddOrStepper(product: p, onAdd: () => _addProduct(p))),
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

/// Collapsible "Order Details" card: storage/counter (table), customer, mobile, loyalty.
class _OrderDetailsCard extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;
  final Cart cart;
  const _OrderDetailsCard({required this.open, required this.onToggle, required this.cart});

  Future<void> _pickTable(BuildContext context) async {
    final s = context.read<Session>();
    final tables = {...?s.activeBranch?.tableNames, ...?s.shop?.settings.tableNames}.toList();
    final t = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Storage / Counter', style: TextStyle(fontWeight: FontWeight.w700))),
          ListTile(leading: const Icon(Icons.block), title: const Text('Not Selected'), onTap: () => Navigator.pop(c, '')),
          if (tables.isEmpty) const ListTile(title: Text('Add tables / counters in Settings or Branches')),
          for (final t in tables) ListTile(leading: const Icon(Icons.table_restaurant_outlined), title: Text(t), selected: cart.tableName == t, onTap: () => Navigator.pop(c, t)),
        ]),
      ),
    );
    if (t != null) cart.setTable(t.isEmpty ? null : t);
  }

  Future<void> _pickCustomer(BuildContext context) async {
    final c = await pickCustomer(context);
    if (c != null) cart.setCustomer(c);
  }

  Future<void> _enterMobile(BuildContext context) async {
    final ctrl = TextEditingController(text: cart.customerPhone);
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Customer Mobile'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          decoration: const InputDecoration(labelText: 'Mobile Number *', prefixIcon: Icon(Icons.phone_android)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (v == null || !context.mounted) return;
    if (v.isEmpty) return cart.setCustomer(null);
    if (!RegExp(r'^\d{10}$').hasMatch(v)) return showSnack(context, 'Must be 10 digits', error: true);
    try {
      cart.setCustomer(Customer(Map<String, dynamic>.from(await Api.instance.get('/customers/phone/$v'))));
    } on ApiException catch (e) {
      if (e.status == 404) cart.setCustomer(null, phone: v, name: 'New Customer');
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = cart.customer?.name ?? (cart.customerPhone?.length == 10 ? (cart.customerName ?? 'New Customer') : 'Walk-in');
    Widget cell(IconData icon, Color color, String label, String value, VoidCallback? onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(children: [
                IconTile(icon, color, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Order Details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text('Storage / Counter: ${cart.tableName ?? 'Not Selected'} • Customer: $customer',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            const SizedBox(width: 8),
          ]),
        ),
        if (open) ...[
          const SizedBox(height: 6),
          Row(children: [
            cell(Icons.storefront, AppColors.blue, 'Storage / Counter', cart.tableName ?? 'Not Selected', () => _pickTable(context)),
            Container(width: 1, height: 40, color: AppColors.border),
            cell(Icons.person, AppColors.green, 'Customer', customer, () => _pickCustomer(context)),
          ]),
          const Divider(height: 1),
          Row(children: [
            cell(Icons.phone_android, AppColors.orange, 'Mobile', cart.customerPhone ?? 'N/A', () => _enterMobile(context)),
            Container(width: 1, height: 40, color: AppColors.border),
            cell(Icons.stars_rounded, const Color(0xFFD4A017), 'Loyalty Points', (cart.customer?.loyaltyPoints ?? 0).toStringAsFixed(1), null),
          ]),
        ],
      ]),
    );
  }
}

/// "+ Add" button, or − qty + stepper when the item is already in the cart.
class _AddOrStepper extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;
  const _AddOrStepper({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final line = cart.lines.where((l) => l.productId == product.id).firstOrNull;
    if (line == null) {
      return SizedBox(
        height: 34,
        width: double.infinity,
        child: TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add'),
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFFEAF2FE),
            foregroundColor: AppColors.blue,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFC9DCF8))),
          ),
        ),
      );
    }
    return Container(
      height: 34,
      decoration: BoxDecoration(color: const Color(0xFFE8F7EF), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        _stepBtn(Icons.remove, AppColors.danger, () => cart.setQty(line, line.quantity - 1)),
        Expanded(
          child: InkWell(
            onTap: () async {
              final v = await askNumber(context, 'Set Quantity (${line.name})', label: 'Quantity', initial: line.quantity);
              if (v != null) cart.setQty(line, v);
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(qty(line.quantity), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.green)),
              const SizedBox(width: 2),
              const Icon(Icons.edit, size: 11, color: AppColors.green),
            ]),
          ),
        ),
        _stepBtn(Icons.add, AppColors.green, () => cart.setQty(line, line.quantity + 1)),
      ]),
    );
  }

  Widget _stepBtn(IconData icon, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          width: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: color),
        ),
      );
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;
  const _ProductCard({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final p = product;
    final cats = context.read<Catalog>().categories;
    final catIndex = cats.indexWhere((c) => c.id == p.categoryId);
    final inCart = context.select<Cart, double>((cart) => cart.lines.where((l) => l.productId == p.id).fold(0.0, (s, l) => s + l.quantity));
    return Material(
      color: inCart > 0 ? const Color(0xFFF2FBF6) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: inCart > 0 ? AppColors.green : AppColors.border, width: inCart > 0 ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAdd,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 112,
            child: Stack(fit: StackFit.expand, children: [
              ProductImage(url: p.imageUrl),
              if (p.categoryName != null)
                Positioned(left: 6, top: 6, child: CornerBadge(p.categoryName!, color: catIndex < 0 ? const Color(0xCC5F6368) : AppColors.forIndex(catIndex).withValues(alpha: .85))),
              if (inCart > 0) Positioned(right: 6, top: 6, child: CornerBadge('${qty(inCart)} in Cart', color: AppColors.green)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                Row(children: [
                  Text(money(p.price).replaceAll('.00', ''), style: const TextStyle(color: AppColors.price, fontWeight: FontWeight.w700, fontSize: 15)),
                  const Spacer(),
                  if (p.trackStock && !p.isExpense) _StockText(p),
                ]),
                const SizedBox(height: 8),
                _AddOrStepper(product: p, onAdd: onAdd),
              ]),
            ),
          ),
        ]),
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
                          leading: CircleAvatar(backgroundColor: const Color(0xFFFFF1E0), child: Text(b.tableName?.characters.first ?? '#', style: const TextStyle(color: StatusColors.waiting))),
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
