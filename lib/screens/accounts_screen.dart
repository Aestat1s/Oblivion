import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/account_service.dart';
import '../models/account.dart';
import '../l10n/app_localizations.dart';
import '../widgets/add_account_dialog.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accountService = context.watch<AccountService>();
    final accounts = accountService.accounts;
    final selectedId = accountService.selectedAccount?.id;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.get('account_management'), style: Theme.of(context).textTheme.headlineMedium),
              FilledButton.icon(
                onPressed: () => _showAddAccountDialog(context),
                icon: const Icon(Icons.add),
                label: Text(l10n.get('add_account')),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: accounts.isEmpty
                ? _buildEmptyState(context, l10n)
                : _buildAccountList(context, accounts, selectedId, accountService, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.person_off, size: 40, color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 16),
          Text(l10n.get('no_accounts'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l10n.get('add_account_hint')),
        ],
      ),
    );
  }

  Widget _buildAccountList(BuildContext context, List<Account> accounts, String? selectedId, AccountService service, AppLocalizations l10n) {
    return ListView.builder(
      itemCount: accounts.length,
      itemBuilder: (context, index) {
        final account = accounts[index];
        final isSelected = account.id == selectedId;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(
                _getAccountIcon(account.type),
                color: isSelected ? Theme.of(context).colorScheme.onPrimary : null,
              ),
            ),
            title: Text(account.username),
            subtitle: Text(_getAccountTypeName(account.type, l10n) + 
                (account.authlibServer != null ? ' • ${account.authlibServer}' : '')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(l10n.get('current'), style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 12,
                    )),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, account, service, l10n),
                ),
              ],
            ),
            onTap: () => service.selectAccount(account.id),
          ),
        );
      },
    );
  }

  IconData _getAccountIcon(AccountType type) => switch (type) {
    AccountType.offline => Icons.person,
    AccountType.microsoft => Icons.window,
    AccountType.authlibInjector => Icons.vpn_key,
  };

  String _getAccountTypeName(AccountType type, AppLocalizations l10n) => switch (type) {
    AccountType.offline => l10n.get('offline_account'),
    AccountType.microsoft => l10n.get('microsoft_account'),
    AccountType.authlibInjector => l10n.get('authlib_account'),
  };

  void _showAddAccountDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => const AddAccountDialog());
  }

  void _confirmDelete(BuildContext context, Account account, AccountService service, AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.get('delete_account')),
        content: Text('${l10n.get('delete_account_confirm')} "${account.username}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.get('cancel'))),
          FilledButton(
            onPressed: () {
              service.removeAccount(account.id);
              Navigator.pop(context);
            },
            child: Text(l10n.get('delete')),
          ),
        ],
      ),
    );
  }
}

