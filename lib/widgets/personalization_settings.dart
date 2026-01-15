import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../services/config_service.dart';
import '../services/theme_service.dart';
import '../models/config.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show applyWindowEffect, applyWindowOpacity;
import 'language_selector_dialog.dart';

class PersonalizationSettings extends StatefulWidget {
  const PersonalizationSettings({super.key});

  @override
  State<PersonalizationSettings> createState() => _PersonalizationSettingsState();
}

class _PersonalizationSettingsState extends State<PersonalizationSettings> {
  final _apiController = TextEditingController();

  @override
  void dispose() {
    _apiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = context.watch<ConfigService>();
    final themeService = context.watch<ThemeService>();
    final settings = config.settings;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, l10n.get('personalization'), Icons.palette),
          Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          ListTile(
            title: Text(l10n.get('language')),
            subtitle: Text(l10n.get('lang_${settings.language}_native')),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (context) => LanguageSelectorDialog(
                    currentLanguage: settings.language,
                  ),
                );
                if (result != null) {
                  settings.language = result;
                  config.save();
                  setState(() {});
                }
              },
              child: Text(l10n.get('select')),
            ),
          ),
          ListTile(
            title: Text(l10n.get('theme')),
            trailing: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l10n.get('theme_system'))),
                ButtonSegment(value: ThemeMode.light, label: Text(l10n.get('theme_light'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(l10n.get('theme_dark'))),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) {
                settings.themeMode = s.first;
                config.save();
                setState(() {});
              },
            ),
          ),
          
          const Divider(),
          _buildBackgroundSection(settings, config, themeService, l10n),
          const Divider(),
          _buildOpacitySection(settings, config, l10n),
          const Divider(),
          _buildThemeColorSection(settings, config, themeService, l10n),
          const Divider(),
          _buildFontSection(settings, config, l10n),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 18),
          ),
          const SizedBox(width: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildBackgroundSection(GlobalSettings settings, ConfigService config, ThemeService themeService, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(l10n.get('background_settings'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.get('bg_none')),
                selected: settings.backgroundType == BackgroundType.none,
                onSelected: (selected) async {
                  if (selected) {
                    settings.backgroundType = BackgroundType.none;
                    config.save();
                    await applyWindowEffect(settings);
                    setState(() {});
                  }
                },
              ),
              ChoiceChip(
                label: Text(l10n.get('bg_image')),
                selected: settings.backgroundType == BackgroundType.image,
                onSelected: (selected) async {
                  if (selected) {
                    settings.backgroundType = BackgroundType.image;
                    config.save();
                    await applyWindowEffect(settings);
                    setState(() {});
                  }
                },
              ),
              ChoiceChip(
                label: Text(l10n.get('bg_random')),
                selected: settings.backgroundType == BackgroundType.randomImage,
                onSelected: (selected) async {
                  if (selected) {
                    await _showRandomImageWarning(l10n);
                    settings.backgroundType = BackgroundType.randomImage;
                    config.save();
                    await applyWindowEffect(settings);
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
        if (settings.backgroundType == BackgroundType.image)
          ListTile(
            title: Text(l10n.get('select_bg_image')),
            subtitle: Text(settings.customBackgroundPath ?? l10n.get('not_selected')),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.image,
                );
                if (result != null && result.files.single.path != null) {
                  settings.customBackgroundPath = result.files.single.path;
                  config.save();
                  await themeService.extractColorFromCurrentBackground(settings);
                  setState(() {});
                }
              },
              child: Text(l10n.get('select')),
            ),
          ),
        if (settings.backgroundType == BackgroundType.randomImage) ...[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _apiController..text = settings.randomImageApi ?? '',
                  decoration: InputDecoration(
                    labelText: l10n.get('random_image_api'),
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    settings.randomImageApi = value;
                    config.save();
                  },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: themeService.isLoadingBackground ? null : () async {
                    settings.randomImageApi = _apiController.text;
                    config.save();
                    await themeService.fetchRandomBackground(settings);
                    setState(() {});
                  },
                  icon: themeService.isLoadingBackground
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(l10n.get('fetch_random_bg')),
                ),
              ],
            ),
          ),
        ],
        if (settings.backgroundType == BackgroundType.image || 
            settings.backgroundType == BackgroundType.randomImage)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l10n.get('bg_blur')),
                    Text('${settings.backgroundBlur.toStringAsFixed(1)}'),
                  ],
                ),
                Slider(
                  value: settings.backgroundBlur,
                  min: 0,
                  max: 20,
                  divisions: 40,
                  onChanged: (v) {
                    settings.backgroundBlur = v;
                    config.save();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildThemeColorSection(GlobalSettings settings, ConfigService config, ThemeService themeService, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(l10n.get('theme_color_settings'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        SwitchListTile(
          title: Text(l10n.get('enable_custom_color')),
          subtitle: Text(l10n.get('custom_color_hint')),
          value: settings.enableCustomColor,
          onChanged: (v) async {
            settings.enableCustomColor = v;
            config.save();
            await themeService.updateThemeColor(settings);
            setState(() {});
          },
        ),
        if (settings.enableCustomColor) ...[
          const Divider(indent: 16, endIndent: 16),
          if (themeService.backgroundExtractedColor != null &&
              (settings.backgroundType == BackgroundType.image ||
               settings.backgroundType == BackgroundType.randomImage))
            ListTile(
              title: Text(l10n.get('bg_extracted_color')),
              subtitle: Text(l10n.get('bg_extracted_hint')),
              trailing: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: themeService.backgroundExtractedColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ),
          
          RadioListTile<ThemeColorSource>(
            title: Text(l10n.get('color_source_system')),
            subtitle: Text(l10n.get('color_source_system_hint')),
            value: ThemeColorSource.system,
            groupValue: settings.themeColorSource,
            onChanged: (v) async {
              if (v != null) {
                settings.themeColorSource = v;
                config.save();
                await themeService.updateThemeColor(settings);
                setState(() {});
              }
            },
          ),
          
          RadioListTile<ThemeColorSource>(
            title: Text(l10n.get('color_source_bg')),
            subtitle: Text(l10n.get('color_source_bg_hint')),
            value: ThemeColorSource.customBackground,
            groupValue: settings.themeColorSource,
            onChanged: (settings.backgroundType == BackgroundType.image ||
                       settings.backgroundType == BackgroundType.randomImage)
                ? (v) async {
                    if (v != null) {
                      settings.themeColorSource = v;
                      config.save();
                      await themeService.extractColorFromCurrentBackground(settings);
                      await themeService.updateThemeColor(settings);
                      setState(() {});
                    }
                  }
                : null,
          ),
          
          RadioListTile<ThemeColorSource>(
            title: Text(l10n.get('color_source_manual')),
            subtitle: Text(l10n.get('color_source_manual_hint')),
            value: ThemeColorSource.manual,
            groupValue: settings.themeColorSource,
            onChanged: (v) async {
              if (v != null) {
                settings.themeColorSource = v;
                config.save();
                await themeService.updateThemeColor(settings);
                setState(() {});
              }
            },
            secondary: settings.themeColorSource == ThemeColorSource.manual
                ? GestureDetector(
                    onTap: () => _showColorPicker(settings, config, themeService, l10n),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: settings.customThemeColor != null
                            ? Color(settings.customThemeColor!)
                            : Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                      ),
                      child: const Icon(Icons.edit, size: 16),
                    ),
                  )
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildFontSection(GlobalSettings settings, ConfigService config, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(l10n.get('font_settings'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        
        ListTile(
          title: Text(l10n.get('custom_font')),
          subtitle: Text(settings.customFontFamily ?? l10n.get('use_default_font')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (settings.customFontFamily != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    settings.customFontFamily = null;
                    config.save();
                    setState(() {});
                  },
                ),
              FilledButton.tonal(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['ttf', 'otf'],
                  );
                  if (result != null && result.files.single.path != null) {
                    settings.customFontFamily = result.files.single.name.split('.').first;
                    config.save();
                    setState(() {});
                    _showRestartDialog(l10n);
                  }
                },
                child: Text(l10n.get('select')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOpacitySection(GlobalSettings settings, ConfigService config, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.get('global_opacity'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            l10n.get('opacity_hint'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.get('opacity')),
              Text('${(settings.windowOpacity * 100).toInt()}%'),
            ],
          ),
          Slider(
            value: settings.windowOpacity,
            min: 0.3,
            max: 1.0,
            divisions: 70,
            onChanged: (v) async {
              settings.windowOpacity = v;
              config.save();
              await applyWindowOpacity(v);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showColorPicker(GlobalSettings settings, ConfigService config, ThemeService themeService, AppLocalizations l10n) async {
    Color pickerColor = settings.customThemeColor != null
        ? Color(settings.customThemeColor!)
        : Theme.of(context).colorScheme.primary;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('select_theme_color')),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) => pickerColor = color,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.get('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              settings.themeColorSource = ThemeColorSource.manual;
              settings.customThemeColor = pickerColor.value;
              config.save();
              await themeService.updateThemeColor(settings);
              setState(() {});
              Navigator.of(context).pop();
            },
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
  }

  Future<void> _showRandomImageWarning(AppLocalizations l10n) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('notice')),
        content: Text(l10n.get('random_image_notice')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.get('i_understand')),
          ),
        ],
      ),
    );
  }

  void _showRestartDialog(AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('notice')),
        content: Text(l10n.get('restart_required')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.get('confirm')),
          ),
        ],
      ),
    );
  }
}
