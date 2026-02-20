// lib/widgets/reader/theme_settings_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/reading_settings.dart';
import '../../providers/reader_state.dart';

class ThemeSettingsSheet extends StatefulWidget {
  final Function(ReadingSettings) onSettingsChanged;

  const ThemeSettingsSheet({
    super.key,
    required this.onSettingsChanged,
  });

  @override
  State<ThemeSettingsSheet> createState() => _ThemeSettingsSheetState();
}

class _ThemeSettingsSheetState extends State<ThemeSettingsSheet> {
  late ReadingSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = context.read<ReaderState>().settings;
  }

  void _updateSettings(ReadingSettings newSettings) {
    setState(() => _settings = newSettings);
    widget.onSettingsChanged(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Theme selection
            Text(
              'Theme',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ReaderTheme.values.map((theme) {
                final isSelected = _settings.theme == theme;
                return GestureDetector(
                  onTap: () => _updateSettings(_settings.copyWith(theme: theme)),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: theme.backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'Aa',
                        style: TextStyle(
                          color: theme.textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Font size
            Text(
              'Font Size',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Row(
              children: [
                const Text('A', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _settings.fontSize,
                    min: 12,
                    max: 28,
                    divisions: 8,
                    label: '${_settings.fontSize.toInt()}',
                    onChanged: (value) => _updateSettings(_settings.copyWith(fontSize: value)),
                  ),
                ),
                const Text('A', style: TextStyle(fontSize: 24)),
              ],
            ),
            const SizedBox(height: 16),

            // Line height
            Text(
              'Line Spacing',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Slider(
              value: _settings.lineHeight,
              min: 1.0,
              max: 2.5,
              divisions: 6,
              label: '${_settings.lineHeight.toStringAsFixed(1)}',
              onChanged: (value) => _updateSettings(_settings.copyWith(lineHeight: value)),
            ),
            const SizedBox(height: 16),

            // Font family
            Text(
              'Font Family',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['Georgia', 'Times New Roman', 'Arial', 'Roboto', 'OpenDyslexic'].map((font) {
                final isSelected = _settings.fontFamily == font;
                return ChoiceChip(
                  label: Text(font, style: TextStyle(fontFamily: font)),
                  selected: isSelected,
                  onSelected: (_) => _updateSettings(_settings.copyWith(fontFamily: font)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Text alignment
            Text(
              'Text Alignment',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAlignmentButton(TextAlign.left, Icons.format_align_left),
                _buildAlignmentButton(TextAlign.center, Icons.format_align_center),
                _buildAlignmentButton(TextAlign.right, Icons.format_align_right),
                _buildAlignmentButton(TextAlign.justify, Icons.format_align_justify),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAlignmentButton(TextAlign alignment, IconData icon) {
    final isSelected = _settings.textAlign == alignment;
    return IconButton(
      onPressed: () => _updateSettings(_settings.copyWith(textAlign: alignment)),
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      ),
    );
  }
}