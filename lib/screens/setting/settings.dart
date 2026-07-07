import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audiobookflow/utils/app_events.dart';
import 'package:provider/provider.dart';
import 'package:audiobookflow/resources/designs/theme_notifier.dart';
import 'package:audiobookflow/resources/latest_version_fetch.dart';
import 'package:audiobookflow/resources/models/latest_version_fetch_model.dart';
import 'package:audiobookflow/screens/four_read_login/four_read_login_screen.dart';
import 'package:audiobookflow/utils/version_compare.dart';

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
  late final Box _settingsBox;
  List<String> _selected = [];
  List<String> _enabledSources = [];
  String _appVersion = '';
  LatestVersionFetchModel? _updateInfo;
  bool _checkingUpdate = false;
  bool _updatingApp = false;

  static const Map<String, String> _sourceLabels = {
    'librivox': 'LibriVox',
    'youtube': 'YouTube',
    'archiveOrg': 'Archive.org',
    'fourRead': '4Read',
    'knigavuhe': 'Knigavuhe',
  };

  @override
  void initState() {
    super.initState();
    _box = Hive.box('language_prefs_box');
    _settingsBox = Hive.box('settings');
    _selected = List<String>.from(
      _box.get('selectedLanguages', defaultValue: <String>[]),
    );
    _enabledSources = List<String>.from(
      _settingsBox.get('enabledSearchSources',
          defaultValue: _sourceLabels.keys.toList()),
    );
    _loadAppVersion();
    _checkForUpdate();
  }

  Future<void> _loadAppVersion() async {
    final info = await PlatformAssetBundle().load('assets/version.json');
    final versionString = String.fromCharCodes(info.buffer.asUint8List());
    setState(() {
      _appVersion = versionString;
    });
  }

  Future<void> _checkForUpdate() async {
    if (_appVersion.isEmpty) return;
    setState(() => _checkingUpdate = true);
    final result = await LatestVersionFetch().getLatestVersion();
    result.fold(
      (_) {},
      (model) {
        if (model.latestVersion != null &&
            compareVersions(model.latestVersion!, _appVersion) > 0) {
          setState(() {
            _updateInfo = model;
            _checkingUpdate = false;
          });
        } else {
          setState(() => _checkingUpdate = false);
        }
      },
    );
    if (_checkingUpdate) setState(() => _checkingUpdate = false);
  }

  Future<void> _downloadAndInstallUpdate() async {
    final updateInfo = _updateInfo;
    if (updateInfo == null || _updatingApp) return;

    setState(() => _updatingApp = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading update...')),
    );

    try {
      await LatestVersionFetch().downloadAndInstallUpdate(updateInfo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening Android installer...')),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final message = e.code == 'INSTALL_PERMISSION_REQUIRED'
          ? 'Allow Flow Book to install updates, then tap Update again.'
          : e.message ?? 'Could not install the update.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _updatingApp = false);
    }
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

  Future<void> _editSearchSources() async {
    final temp = {..._enabledSources};
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Search Sources'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: _sourceLabels.entries.map((e) {
                final key = e.key;
                final label = e.value;
                final checked = temp.contains(key);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (v) {
                    setState(() {});
                    if (v == true) {
                      temp.add(key);
                    } else {
                      temp.remove(key);
                    }
                    (ctx as Element).markNeedsBuild();
                  },
                  title: Text(label),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
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
                await _settingsBox.put('enabledSearchSources', temp.toList());
                setState(() {
                  _enabledSources = temp.toList();
                });
                AppEvents.searchSourcesChanged.add(null); // broadcast refresh
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Search sources updated.'),
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

          // Search sources
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search Sources'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _enabledSources
                    .map((s) => Chip(
                          label: Text(_sourceLabels[s] ?? s),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ),
            trailing: const Icon(Icons.edit),
            onTap: _editSearchSources,
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

          // Update available indicator
          if (_updateInfo != null) ...[
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  color: Colors.orange.shade700,
                  size: 22,
                ),
              ),
              title: Text(
                'Update Available',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade800,
                ),
              ),
              subtitle: Text(
                'Version ${_updateInfo!.latestVersion}',
                style: TextStyle(color: Colors.orange.shade600),
              ),
              trailing: _updatingApp
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'NEW',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
              onTap: _updatingApp ? null : _downloadAndInstallUpdate,
            ),
            const Divider(),
          ],

          // Version
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(_appVersion.isNotEmpty ? _appVersion : '1.1.1'),
            trailing: _checkingUpdate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
