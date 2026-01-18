import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/account_service.dart';
import '../l10n/app_localizations.dart';

class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  int _selectedType = 0;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.get('add_account')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(l10n.get('offline')), icon: const Icon(Icons.person)),
                ButtonSegment(value: 1, label: Text(l10n.get('microsoft')), icon: const Icon(Icons.window)),
                ButtonSegment(value: 2, label: Text(l10n.get('authlib')), icon: const Icon(Icons.vpn_key)),
              ],
              selected: {_selectedType},
              onSelectionChanged: (set) => setState(() {
                _selectedType = set.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 20),
            if (_selectedType == 0) _buildOfflineForm(l10n),
            if (_selectedType == 1) _buildMicrosoftForm(l10n),
            if (_selectedType == 2) _buildAuthlibForm(l10n),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_selectedType == 1 ? l10n.get('login') : l10n.get('add')),
        ),
      ],
    );
  }

  Widget _buildOfflineForm(AppLocalizations l10n) {
    return TextField(
      controller: _usernameController,
      decoration: InputDecoration(
        labelText: l10n.get('username'),
        hintText: l10n.get('username_hint'),
      ),
      autofocus: true,
    );
  }

  Widget _buildMicrosoftForm(AppLocalizations l10n) {
    return Column(
      children: [
        const Icon(Icons.open_in_browser, size: 48),
        const SizedBox(height: 12),
        Text(l10n.get('microsoft_login_instruction')),
      ],
    );
  }

  Widget _buildAuthlibForm(AppLocalizations l10n) {
    
    final commonServers = [
      {'name': 'LittleSkin', 'url': 'https://littleskin.cn/api/yggdrasil'},
      {'name': 'Blessing Skin', 'url': 'https://skin.prinzeugen.net/api/yggdrasil'},
      {'name': '自定义', 'url': ''},
    ];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        
        Text(l10n.get('auth_server'), style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: commonServers.map((server) {
            final isSelected = _serverController.text == server['url'];
            return FilterChip(
              label: Text(server['name']!),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _serverController.text = server['url']!;
                  });
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        
        TextField(
          controller: _serverController,
          decoration: InputDecoration(
            labelText: l10n.get('server_url'),
            hintText: 'https://example.com/api/yggdrasil',
            helperText: '支持 authlib-injector 协议的皮肤站',
            prefixIcon: const Icon(Icons.link),
            suffixIcon: _serverController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _serverController.clear()),
                  )
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: l10n.get('email_username'),
            hintText: '邮箱或用户名',
            prefixIcon: const Icon(Icons.person),
          ),
          autofocus: false,
        ),
        const SizedBox(height: 12),
        
        TextField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: l10n.get('password'),
            prefixIcon: const Icon(Icons.lock),
          ),
          obscureText: true,
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final accountService = context.read<AccountService>();
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      switch (_selectedType) {
        case 0: 
          final username = _usernameController.text.trim();
          if (username.isEmpty) {
            setState(() => _error = l10n.get('error_empty_username'));
            return;
          }
          await accountService.addOfflineAccount(username);
          break;
          
        case 1: 
          await accountService.loginMicrosoft();
          break;
          
        case 2: 
          final server = _serverController.text.trim();
          final username = _usernameController.text.trim();
          final password = _passwordController.text;
          
          if (server.isEmpty) {
            setState(() => _error = l10n.get('error_empty_server'));
            return;
          }
          if (username.isEmpty || password.isEmpty) {
            setState(() => _error = l10n.get('error_empty_credentials'));
            return;
          }
          
          await accountService.loginAuthlib(server, username, password);
          break;
      }
      
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
