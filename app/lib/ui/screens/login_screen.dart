import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../state/session.dart';
import '../../core/theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().login(_email.text, _password.text);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final form = _formCard(context);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          const Expanded(child: _BrandPanel(wide: true)),
          Expanded(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: form))),
        ]),
      );
    }
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          const _BrandPanel(wide: false),
          Transform.translate(offset: const Offset(0, -36), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: form)),
        ]),
      ),
    );
  }

  Widget _formCard(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Welcome back', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              const SizedBox(height: 4),
              const Text('Sign in to your OnePe POS account', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500)),
              const SizedBox(height: 22),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Please enter your email';
                  if (!v.contains('@')) return 'Please enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure)),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Please enter your password' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: c.error, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              GreenButton(label: 'Sign in', icon: Icons.arrow_forward_rounded, busy: _busy, onPressed: _submit, height: 54),
              const SizedBox(height: 8),
              TextButton.icon(onPressed: () => _contactUs(context), icon: const Icon(Icons.support_agent), label: const Text('New business? Contact us')),
              Text('Version ${AppConfig.version}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _contactUs(BuildContext context) async {
    final name = TextEditingController(), business = TextEditingController(), phone = TextEditingController(), location = TextEditingController();
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Contact Us'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 8),
            TextField(controller: business, decoration: const InputDecoration(labelText: 'Business Type (e.g., Bakery, Retail)')),
            const SizedBox(height: 8),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact Number')),
            const SizedBox(height: 8),
            TextField(controller: location, decoration: const InputDecoration(labelText: 'Location')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final ok = await guard(c, () => Api.instance.post('/public/enquiries', {
                    'name': name.text, 'businessType': business.text, 'contactNo': phone.text, 'location': location.text,
                  }), success: 'Thanks! Our team will contact you shortly.');
              if (ok != null && c.mounted) Navigator.pop(c);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}

/// OnePe Blue brand panel with the lime logo, tagline and the brand's lime stepped edge.
class _BrandPanel extends StatelessWidget {
  final bool wide;
  const _BrandPanel({required this.wide});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: wide ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        BrandLogo(height: wide ? 64 : 44, lime: true),
        SizedBox(height: wide ? 36 : 22),
        Text('Your Business.\nAll In One.',
            style: TextStyle(color: Colors.white, fontSize: wide ? 44 : 28, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
        const SizedBox(height: 12),
        Text('Billing, stock, customers and reports –\nfrom one connected platform.',
            style: TextStyle(color: const Color(0xFFC9D6EA), fontSize: wide ? 17 : 14, fontWeight: FontWeight.w500, height: 1.4)),
      ],
    );
    return Stack(children: [
      Positioned(
        left: 0,
        bottom: 0,
        width: wide ? 260 : 220,
        height: 90,
        child: Container(decoration: const BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.only(topRight: Radius.circular(36)))),
      ),
      Container(
        width: double.infinity,
        height: wide ? MediaQuery.of(context).size.height : null,
        margin: EdgeInsets.only(bottom: wide ? 0 : 10, right: wide ? 10 : 0),
        padding: EdgeInsets.fromLTRB(wide ? 64 : 24, top + (wide ? 40 : 36), 24, wide ? 40 : 72),
        decoration: BoxDecoration(
          color: AppColors.blue,
          borderRadius: wide ? const BorderRadius.only(topRight: Radius.circular(40), bottomRight: Radius.circular(40)) : const BorderRadius.vertical(bottom: Radius.circular(36)),
        ),
        child: content,
      ),
    ]);
  }
}
