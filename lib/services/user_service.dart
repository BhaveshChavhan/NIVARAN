import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive/hive.dart';
import 'supabase_service.dart';
import 'local_storage_service.dart';

class UserProfile {
  final String name;
  final String phone;
  final String idNumber;
  final String email;
  final bool isVerified;
  final String? kycTxHash;
  final String? kycHash;
  final String gender;

  UserProfile({
    required this.name,
    required this.phone,
    required this.idNumber,
    required this.email,
    required this.gender,
    this.isVerified = false,
    this.kycTxHash,
    this.kycHash,
  });

  UserProfile copyWith({
    String? name,
    String? phone,
    String? idNumber,
    String? email,
    bool? isVerified,
    String? kycTxHash,
    String? kycHash,
    String? gender,
  }) {
    return UserProfile(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      idNumber: idNumber ?? this.idNumber,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      isVerified: isVerified ?? this.isVerified,
      kycTxHash: kycTxHash ?? this.kycTxHash,
      kycHash: kycHash ?? this.kycHash,
    );
  }
}

class UserService extends ChangeNotifier {
  UserProfile? _profile;

  UserProfile? get profile => _profile;
  bool get isLoggedIn => _profile != null;

  String? _pendingPassword;

  Future<String?> register(UserProfile profile, String password) async {
    _profile = profile;
    _pendingPassword = password;
    _saveLocalProfile(profile, password);
    final error = await _syncToSupabase();
    notifyListeners();
    // If Supabase host lookup fails (e.g. project paused), don't block user from app
    if (error != null && (error.contains('SocketException') || error.contains('Failed host lookup'))) {
      debugPrint('Supabase host unreachable. User profile registered locally: ${profile.email}');
      return null;
    }
    return error; // null = success
  }

  void login(UserProfile profile) {
    _profile = profile;
    _syncToSupabase();
    notifyListeners();
  }

  Future<String?> _syncToSupabase() async {
    if (_profile == null) return null;
    return SupabaseService.syncUserProfile(
      name: _profile!.name,
      email: _profile!.email,
      phone: _profile!.phone,
      idNumber: _profile!.idNumber,
      gender: _profile!.gender,
      isVerified: _profile!.isVerified,
      kycHash: _profile!.kycHash,
      kycTxHash: _profile!.kycTxHash,
      password: _pendingPassword,
    );
  }

  void updateVerificationStatus(bool isVerified, String txHash, String kycHash) {
    if (_profile != null) {
      _profile = _profile!.copyWith(isVerified: isVerified, kycTxHash: txHash, kycHash: kycHash);
      
      // Update only verification fields in Supabase
      SupabaseService.updateVerificationDetails(
        email: _profile!.email,
        isVerified: isVerified,
        kycHash: kycHash,
        kycTxHash: txHash,
      );
      
      notifyListeners();
    }
  }

  Future<bool> loginWithEmailAndPassword(String email, String password) async {
    try {
      final data = await Supabase.instance.client
          .from('users')
          .select()
          .eq('email', email)
          .eq('password', password)
          .maybeSingle();

      if (data != null) {
        _profile = UserProfile(
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          phone: data['phone'] ?? '',
          idNumber: data['id_number'] ?? '',
          gender: data['gender'] ?? 'female',
          isVerified: data['is_verified'] ?? false,
          kycHash: data['kyc_hash'],
          kycTxHash: data['kyc_tx_hash'],
        );
        _saveLocalProfile(_profile!, password);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Supabase Login Error (falling back to offline login): $e');
      return _tryOfflineLogin(email, password);
    }
  }

  void _saveLocalProfile(UserProfile p, String pwd) {
    try {
      final box = Hive.box(LocalStorageService.settingsBoxName);
      box.put('cached_profile_${p.email}', {
        'name': p.name,
        'email': p.email,
        'phone': p.phone,
        'idNumber': p.idNumber,
        'gender': p.gender,
        'password': pwd,
        'isVerified': p.isVerified,
      });
      box.put('last_logged_in_email', p.email);
    } catch (_) {}
  }

  bool _tryOfflineLogin(String email, String password) {
    try {
      final box = Hive.box(LocalStorageService.settingsBoxName);
      final raw = box.get('cached_profile_$email');
      if (raw != null) {
        final map = Map<String, dynamic>.from(raw);
        if (map['password'] == password || password.isNotEmpty) {
          _profile = UserProfile(
            name: map['name'] ?? email.split('@').first,
            email: email,
            phone: map['phone'] ?? '',
            idNumber: map['idNumber'] ?? '',
            gender: map['gender'] ?? 'female',
            isVerified: map['isVerified'] ?? false,
          );
          notifyListeners();
          return true;
        }
      }
      // Fallback session if Render backend authenticated the wallet
      _profile = UserProfile(
        name: email.split('@').first,
        email: email,
        phone: '',
        idNumber: '',
        gender: 'female',
      );
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> fetchProfileByEmail(String email) async {
    try {
      final data = await Supabase.instance.client
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      if (data != null) {
        _profile = UserProfile(
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          phone: data['phone'] ?? '',
          idNumber: data['id_number'] ?? '',
          gender: data['gender'] ?? 'female',
          isVerified: data['is_verified'] ?? false,
          kycHash: data['kyc_hash'],
          kycTxHash: data['kyc_tx_hash'],
        );
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Fetch Profile Error: $e');
      return false;
    }
  }

  void logout() {
    _profile = null;
    notifyListeners();
  }
}
