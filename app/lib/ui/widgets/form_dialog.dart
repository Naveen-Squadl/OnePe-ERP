import 'package:flutter/material.dart';

/// Field spec for [showFormDialog].
class FieldSpec {
  final String key;
  final String label;
  final String? initial;
  final bool required;
  final TextInputType? keyboard;
  final bool obscure;
  final String? Function(String)? validator;
  const FieldSpec(this.key, this.label, {this.initial, this.required = false, this.keyboard, this.obscure = false, this.validator});
}

/// Simple dialog form returning field values, or null if cancelled.
Future<Map<String, String>?> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  String submit = 'Save',
  Widget? extra,
}) {
  final form = GlobalKey<FormState>();
  final ctrls = {for (final f in fields) f.key: TextEditingController(text: f.initial ?? '')};
  return showDialog<Map<String, String>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final f in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(
                    controller: ctrls[f.key],
                    keyboardType: f.keyboard,
                    obscureText: f.obscure,
                    decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : '')),
                    validator: (v) {
                      if (f.required && (v == null || v.trim().isEmpty)) return 'Required';
                      return f.validator?.call(v ?? '');
                    },
                  ),
                ),
              ?extra,
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(c, {for (final e in ctrls.entries) e.key: e.value.text.trim()});
          },
          child: Text(submit),
        ),
      ],
    ),
  );
}
