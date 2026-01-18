import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/account.dart';
import 'config_service.dart';

class AccountService extends ChangeNotifier {
  final ConfigService _configService;
  
  
  static const String _msClientId = '00000000402b5328'; 
  static const String _msRedirectUri = 'https://login.live.com/oauth20_desktop.srf';
  static const String _msScope = 'XboxLive.signin offline_access';
  
  bool _isMicrosoftLoggingIn = false;
  String _microsoftLoginStatus = '';
  
  AccountService(this._configService);

  List<Account> get accounts => _configService.config.accounts;
  bool get isMicrosoftLoggingIn => _isMicrosoftLoggingIn;
  String get microsoftLoginStatus => _microsoftLoginStatus;
  
  Account? get selectedAccount {
    final id = _configService.config.selectedAccountId;
    if (id == null) return null;
    try {
      return accounts.firstWhere((a) => a.id == id);
    } catch (_) {
      return accounts.isNotEmpty ? accounts.first : null;
    }
  }

  Future<void> addOfflineAccount(String username) async {
    final account = Account.offline(username);
    _configService.config.accounts.add(account);
    _configService.config.selectedAccountId = account.id;
    await _configService.save();
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    _configService.config.accounts.removeWhere((a) => a.id == id);
    if (_configService.config.selectedAccountId == id) {
      _configService.config.selectedAccountId = 
          accounts.isNotEmpty ? accounts.first.id : null;
    }
    await _configService.save();
    notifyListeners();
  }

  Future<void> selectAccount(String id) async {
    _configService.config.selectedAccountId = id;
    final account = accounts.firstWhere((a) => a.id == id);
    account.lastUsed = DateTime.now();
    await _configService.save();
    notifyListeners();
  }

  
  String getMicrosoftLoginUrl() {
    return 'https://login.live.com/oauth20_authorize.srf'
        '?client_id=$_msClientId'
        '&response_type=code'
        '&redirect_uri=${Uri.encodeComponent(_msRedirectUri)}'
        '&scope=${Uri.encodeComponent(_msScope)}';
  }

  
  Future<void> openMicrosoftLogin() async {
    final url = getMicrosoftLoginUrl();
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  
  Future<void> loginMicrosoft() async {
    _isMicrosoftLoggingIn = true;
    _microsoftLoginStatus = '正在打开登录页面...';
    notifyListeners();

    try {
      await openMicrosoftLogin();
      _microsoftLoginStatus = '请在浏览器中完成登录，然后复制授权码';
      notifyListeners();
      
      
      
      throw Exception('请在浏览器中完成登录后，复制 URL 中的 code 参数并使用 loginMicrosoftWithCode 方法');
    } catch (e) {
      _microsoftLoginStatus = e.toString();
      rethrow;
    } finally {
      _isMicrosoftLoggingIn = false;
      notifyListeners();
    }
  }

  
  Future<void> loginMicrosoftWithCode(String code) async {
    _isMicrosoftLoggingIn = true;
    _microsoftLoginStatus = '正在获取访问令牌...';
    notifyListeners();

    try {
      
      _microsoftLoginStatus = '正在获取 Microsoft 令牌...';
      notifyListeners();
      
      final tokenResponse = await http.post(
        Uri.parse('https://login.live.com/oauth20_token.srf'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _msClientId,
          'code': code,
          'grant_type': 'authorization_code',
          'redirect_uri': _msRedirectUri,
        },
      );

      if (tokenResponse.statusCode != 200) {
        throw Exception('获取 Microsoft 令牌失败');
      }

      final tokenData = jsonDecode(tokenResponse.body);
      final msAccessToken = tokenData['access_token'];
      final msRefreshToken = tokenData['refresh_token'];

      
      _microsoftLoginStatus = '正在进行 Xbox Live 认证...';
      notifyListeners();
      
      final xblResponse = await http.post(
        Uri.parse('https://user.auth.xboxlive.com/user/authenticate'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'Properties': {
            'AuthMethod': 'RPS',
            'SiteName': 'user.auth.xboxlive.com',
            'RpsTicket': 'd=$msAccessToken',
          },
          'RelyingParty': 'http://auth.xboxlive.com',
          'TokenType': 'JWT',
        }),
      );

      if (xblResponse.statusCode != 200) {
        throw Exception('Xbox Live 认证失败');
      }

      final xblData = jsonDecode(xblResponse.body);
      final xblToken = xblData['Token'];
      final userHash = xblData['DisplayClaims']['xui'][0]['uhs'];

      
      _microsoftLoginStatus = '正在获取 XSTS 令牌...';
      notifyListeners();
      
      final xstsResponse = await http.post(
        Uri.parse('https://xsts.auth.xboxlive.com/xsts/authorize'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'Properties': {
            'SandboxId': 'RETAIL',
            'UserTokens': [xblToken],
          },
          'RelyingParty': 'rp://api.minecraftservices.com/',
          'TokenType': 'JWT',
        }),
      );

      if (xstsResponse.statusCode != 200) {
        final xstsError = jsonDecode(xstsResponse.body);
        if (xstsError['XErr'] == 2148916233) {
          throw Exception('此 Microsoft 账户没有 Xbox 账户');
        } else if (xstsError['XErr'] == 2148916238) {
          throw Exception('此账户是未成年人账户，需要家长同意');
        }
        throw Exception('XSTS 认证失败');
      }

      final xstsData = jsonDecode(xstsResponse.body);
      final xstsToken = xstsData['Token'];

      
      _microsoftLoginStatus = '正在获取 Minecraft 令牌...';
      notifyListeners();
      
      final mcResponse = await http.post(
        Uri.parse('https://api.minecraftservices.com/authentication/login_with_xbox'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identityToken': 'XBL3.0 x=$userHash;$xstsToken',
        }),
      );

      if (mcResponse.statusCode != 200) {
        throw Exception('Minecraft 认证失败');
      }

      final mcData = jsonDecode(mcResponse.body);
      final mcAccessToken = mcData['access_token'];

      
      _microsoftLoginStatus = '正在验证游戏所有权...';
      notifyListeners();
      
      final ownershipResponse = await http.get(
        Uri.parse('https://api.minecraftservices.com/entitlements/mcstore'),
        headers: {'Authorization': 'Bearer $mcAccessToken'},
      );

      if (ownershipResponse.statusCode == 200) {
        final ownershipData = jsonDecode(ownershipResponse.body);
        final items = ownershipData['items'] as List;
        if (items.isEmpty) {
          throw Exception('此账户没有购买 Minecraft');
        }
      }

      
      _microsoftLoginStatus = '正在获取玩家档案...';
      notifyListeners();
      
      final profileResponse = await http.get(
        Uri.parse('https://api.minecraftservices.com/minecraft/profile'),
        headers: {'Authorization': 'Bearer $mcAccessToken'},
      );

      if (profileResponse.statusCode != 200) {
        throw Exception('获取玩家档案失败，可能没有创建角色');
      }

      final profileData = jsonDecode(profileResponse.body);

      
      final account = Account(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: AccountType.microsoft,
        username: profileData['name'],
        uuid: profileData['id'],
        accessToken: mcAccessToken,
        refreshToken: msRefreshToken,
      );

      _configService.config.accounts.add(account);
      _configService.config.selectedAccountId = account.id;
      await _configService.save();

      _microsoftLoginStatus = '登录成功！';
    } catch (e) {
      _microsoftLoginStatus = '登录失败: $e';
      rethrow;
    } finally {
      _isMicrosoftLoggingIn = false;
      notifyListeners();
    }
  }

  
  Future<bool> refreshMicrosoftToken(Account account) async {
    final refreshToken = account.refreshToken;
    if (account.type != AccountType.microsoft) {
      return false;
    }

    try {
      final tokenResponse = await http.post(
        Uri.parse('https://login.live.com/oauth20_token.srf'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _msClientId,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (tokenResponse.statusCode != 200) return false;

      final tokenData = jsonDecode(tokenResponse.body);
      
      
      account.refreshToken = tokenData['refresh_token'];
      await _configService.save();
      return true;
    } catch (e) {
      debugPrint('Failed to refresh Microsoft token: $e');
      return false;
    }
  }

  
  Future<void> loginAuthlib(String serverUrl, String username, String password) async {
    var server = serverUrl.trim();
    if (!server.startsWith('http')) {
      server = 'https://$server';
    }
    if (!server.contains('/api/yggdrasil') && !server.endsWith('/authserver')) {
      if (server.endsWith('/')) server = server.substring(0, server.length - 1);
      try {
        final metaResponse = await http.get(Uri.parse(server));
        if (metaResponse.statusCode == 200) {
          jsonDecode(metaResponse.body);
        }
      } catch (_) {}
    }

    final authUrl = server.endsWith('/authserver') 
        ? '$server/authenticate'
        : '$server/authserver/authenticate';

    final response = await http.post(
      Uri.parse(authUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'agent': {'name': 'Minecraft', 'version': 1},
        'username': username,
        'password': password,
        'requestUser': true,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['errorMessage'] ?? '登录失败');
    }

    final data = jsonDecode(response.body);
    final selectedProfile = data['selectedProfile'];
    
    if (selectedProfile == null) {
      throw Exception('该账户没有可用的游戏角色');
    }

    final account = Account(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: AccountType.authlibInjector,
      username: selectedProfile['name'],
      uuid: selectedProfile['id'],
      accessToken: data['accessToken'],
      authlibServer: server,
    );

    _configService.config.accounts.add(account);
    _configService.config.selectedAccountId = account.id;
    await _configService.save();
    notifyListeners();
  }

  
  Future<bool> refreshAuthlibToken(Account account) async {
    if (account.type != AccountType.authlibInjector || account.authlibServer == null) {
      return false;
    }

    final server = account.authlibServer!;
    final refreshUrl = server.endsWith('/authserver')
        ? '$server/refresh'
        : '$server/authserver/refresh';

    try {
      final response = await http.post(
        Uri.parse(refreshUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'accessToken': account.accessToken,
          'requestUser': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        account.accessToken = data['accessToken'];
        await _configService.save();
        return true;
      }
    } catch (e) {
      debugPrint('Failed to refresh token: $e');
    }
    return false;
  }

  
  Future<bool> validateToken(Account account) async {
    if (account.type == AccountType.offline) return true;
    
    if (account.type == AccountType.authlibInjector && account.authlibServer != null) {
      final server = account.authlibServer!;
      final validateUrl = server.endsWith('/authserver')
          ? '$server/validate'
          : '$server/authserver/validate';

      try {
        final response = await http.post(
          Uri.parse(validateUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'accessToken': account.accessToken}),
        );
        return response.statusCode == 204;
      } catch (_) {
        return false;
      }
    }
    
    return false;
  }
}
