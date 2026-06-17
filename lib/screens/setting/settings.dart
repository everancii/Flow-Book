import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audiobookflow/utils/app_events.dart';
import 'package:audiobookflow/resources/services/local/local_audiobook_service.dart';
import 'package:audiobookflow/resources/designs/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:audiobookflow/resources/designs/theme_notifier.dart';
import 'package:saf/saf.dart';
import 'package:audiobookflow/screens/setting/listening_stats_screen.dart';
import 'package:audiobookflow/screens/four_read_login/four_read_login_screen.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  // Used from archive.org/details/librivoxaudio 's language filter, sorted
  static const Map<String, String> _langs = {
    'en': 'English',
    'de': 'Deutsch (German)',
    'es': 'Español (Spanish)',
    'fr': 'Français (French)',
    'nl': 'Nederlands (Dutch)',
    'mul': 'Multiple / Multilingual',
    'pt': 'Português (Portuguese)',
    'it': 'Italian (Italian)',
    'ru': 'Русский (Russian)',
    'uk': 'Українська (Ukrainian)',
    'el': 'Ελληνικά (Greek)',
    'grc': 'Ancient Greek',
    'ja': '日本語 (Japanese)',
    'pl': 'Polski (Polish)',
    'zh': '中文 (Chinese)',
    'he': 'עברית (Hebrew)',
    'la': 'Latina (Latin)',
    'fi': 'Suomi (Finnish)',
    'sv': 'Svenska (Swedish)',
    'ca': 'Català (Catalan)',
    'da': 'Dansk (Danish)',
    'eo': 'Esperanto',
  };

  late final Box _box;
  List<String> _selected = [];
  String? _rootFolderPath;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _box = Hive.box('language_prefs_box');
    _selected = List<String>.from(
      _box.get('selectedLanguages', defaultValue: <String>[]),
    );
    _loadRootFolderPath();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PlatformAssetBundle().load('assets/version.json');
    final versionString = String.fromCharCodes(info.buffer.asUint8List());
    setState(() {
      _appVersion = versionString;
    });
  }

  Future<void> _loadRootFolderPath() async {
    final path = await LocalAudiobookService.getRootFolderPath();
    setState(() {
      _rootFolderPath = path;
    });
  }

  Future<void> _editLanguages() async {
    final temp = {..._selected}; // work on a copy in the dialog
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Visible languages'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: _langs.entries.map((e) {
                final code = e.key;
                final label = e.value;
                final checked = temp.contains(code);
                return Column(
                  children: [
                    CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setState(() {}); // keep dialog snappy
                        if (v == true) {
                          temp.add(code);
                        } else {
                          temp.remove(code);
                        }
                        // force rebuild of dialog
                        (ctx as Element).markNeedsBuild();
                      },
                      title: Text(label),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                // Persist selection
                await _box.put('selectedLanguages', temp.toList()..sort());
                setState(() {
                  _selected = temp.toList()..sort();
                });
                AppEvents.languagesChanged.add(null); // <-- broadcast refresh
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Language filter saved. Lists will update on next fetch.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectRootFolder() async {
    try {
      await Saf.releasePersistedPermissions();

      // Use SAF to get dynamic directory permission (user chooses folder)
      bool? isGranted = await Saf.getDynamicDirectoryPermission();

      if (isGranted == true) {
        // Get the list of persisted permission directories
        List<String>? persistedDirectories =
            await Saf.getPersistedPermissionDirectories();

        if (persistedDirectories != null && persistedDirectories.isNotEmpty) {
          // Use the most recently granted directory
          String selectedDirectory = persistedDirectories.last;

          await LocalAudiobookService.setRootFolderPath(selectedDirectory);

          // Clear all caches for the new folder
          await LocalAudiobookService.clearAllCaches();

          setState(() {
            _rootFolderPath = selectedDirectory;
          });

          // Notify other screens about the directory change
          AppEvents.localDirectoryChanged.add(null);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Audiobooks directory updated successfully!'),
                backgroundColor: AppColors.primaryColor,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No directory was selected'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Directory access permission denied or selection cancelled'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _themeSubtitle(AppTheme theme) {
    switch (theme) {
      case AppTheme.light:
        return 'White (Light)';
      case AppTheme.dark:
        return 'Dark';
      case AppTheme.blue:
        return 'Blue';
    }
  }

  Future<void> _pickTheme(BuildContext context) async {
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);
    AppTheme current = themeNotifier.currentTheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AppTheme>(
              title: const Text('White (Light)'),
              value: AppTheme.light,
              groupValue: current,
              onChanged: (v) {
                if (v == null) return;
                themeNotifier.setTheme(v);
                Navigator.of(ctx).pop();
              },
            ),
            RadioListTile<AppTheme>(
              title: const Text('Dark'),
              value: AppTheme.dark,
              groupValue: current,
              onChanged: (v) {
                if (v == null) return;
                themeNotifier.setTheme(v);
                Navigator.of(ctx).pop();
              },
            ),
            RadioListTile<AppTheme>(
              title: const Text('Blue'),
              value: AppTheme.blue,
              groupValue: current,
              onChanged: (v) {
                if (v == null) return;
                themeNotifier.setTheme(v);
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );

    if (mounted) setState(() {}); // refresh subtitle after change
  }

  @override
  Widget build(BuildContext context) {
    final chips = _selected.isEmpty
        ? [const Chip(label: Text('All languages (no filter)'))]
        : _selected.map((c) => Chip(label: Text(_langs[c] ?? c))).toList();

    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final currentTheme = themeNotifier.currentTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Theme selection (moved from App Bar)
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            subtitle: Text(_themeSubtitle(currentTheme)),
            trailing: const Icon(Icons.edit),
            onTap: () => _pickTheme(context),
          ),
          const Divider(),

          // Language filter
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Visible languages'),
            subtitle: Wrap(
              spacing: 8,
              runSpacing: -8,
              children: chips,
            ),
            trailing: const Icon(Icons.edit),
            onTap: _editLanguages,
          ),
          const Divider(),

          // Local Audiobooks Directory
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Local Books Directory'),
            subtitle: Text(
              _rootFolderPath ?? 'No directory selected',
              style: TextStyle(
                color: _rootFolderPath != null
                    ? Theme.of(context).textTheme.bodySmall?.color
                    : Colors.grey,
              ),
            ),
            trailing: const Icon(Icons.edit),
            onTap: _selectRootFolder,
          ),
          const Divider(),

          // 4Read Login
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('4Read Login'),
            subtitle: const Text('Login to access exclusive audiobooks'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FourReadLoginScreen(),
                ),
              );
            },
          ),
          const Divider(),

          // Version
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(_appVersion.isNotEmpty ? _appVersion : '1.1.1'),
          ),
        ],
      ),
    );
  }
}
