import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class LanguageSelectorDialog extends StatefulWidget {
  final String currentLanguage;

  const LanguageSelectorDialog({
    super.key,
    required this.currentLanguage,
  });

  @override
  State<LanguageSelectorDialog> createState() => _LanguageSelectorDialogState();
}

class _LanguageSelectorDialogState extends State<LanguageSelectorDialog> {
  late String _selectedLanguage;
  String _searchQuery = '';

  static const List<String> _languageCodes = ['zh', 'en'];

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.currentLanguage;
  }

  List<Map<String, String>> _getLanguages(AppLocalizations l10n) {
    return _languageCodes.map((code) => {
      'code': code,
      'name': l10n.get('lang_$code'),
      'native': l10n.get('lang_${code}_native'),
    }).toList();
  }

  List<Map<String, String>> _getFilteredLanguages(AppLocalizations l10n) {
    final languages = _getLanguages(l10n);
    if (_searchQuery.isEmpty) return languages;
    
    return languages.where((lang) {
      final name = lang['name']!.toLowerCase();
      final native = lang['native']!.toLowerCase();
      final code = lang['code']!.toLowerCase();
      final query = _searchQuery.toLowerCase();
      
      return name.contains(query) || native.contains(query) || code.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final filteredLanguages = _getFilteredLanguages(l10n);
    
    return Dialog(
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.get('select_language'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      hintText: l10n.get('search_language'),
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredLanguages.length,
                itemBuilder: (context, index) {
                  final lang = filteredLanguages[index];
                  final isSelected = lang['code'] == _selectedLanguage;
                  
                  return ListTile(
                    title: Text(lang['name']!),
                    subtitle: Text(lang['native']!),
                    trailing: isSelected
                        ? Icon(Icons.check, color: colorScheme.primary)
                        : null,
                    selected: isSelected,
                    onTap: () {
                      setState(() => _selectedLanguage = lang['code']!);
                    },
                  );
                },
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.get('cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selectedLanguage),
                    child: Text(l10n.get('confirm')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
