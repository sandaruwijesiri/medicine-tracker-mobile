import 'package:flutter/material.dart';

Future<String?> pickChoice(
  BuildContext context, {
  required String title,
  required Map<String, String> options,
  String? selected,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) =>
      _ChoiceSheet(title: title, options: options, selected: selected),
);

class ChoiceField extends StatelessWidget {
  const ChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: !enabled
          ? null
          : () async {
              final result = await pickChoice(
                context,
                title: label,
                options: options,
                selected: value,
              );
              if (result != null) onChanged(result);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: const Icon(Icons.expand_more),
        ),
        child: Text(
          options[value] ?? 'Choose $label',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet({
    required this.title,
    required this.options,
    this.selected,
  });
  final String title;
  final Map<String, String> options;
  final String? selected;
  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final matches = widget.options.entries
        .where((e) => e.value.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Search ${widget.title.toLowerCase()}',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('No matching options'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final item = matches[index];
                        return ListTile(
                          title: Text(item.value),
                          selected: item.key == widget.selected,
                          trailing: item.key == widget.selected
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(context, item.key),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
