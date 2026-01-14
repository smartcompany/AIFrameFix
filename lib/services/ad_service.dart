import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdService {
  AdService._() {
    // baseUrl은 나중에 설정
  }
  static final AdService shared = AdService._();

  String _baseUrl = '';
  bool _settingsLoaded = false;
  bool _isLoadingSettings = false;
  String? _rewardedAdId;
  String? _initialAdId;
  RewardedAd? _rewardedAd;
  bool _isRewardedAdReady = false;

  String? get rewardedAdId => _rewardedAdId;
  String? get initialAdId => _initialAdId;

  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  Future<bool> loadSettings() async {
    // 이미 로드했거나 로딩 중이면 재호출하지 않음
    if (_settingsLoaded || _isLoadingSettings) {
      return _settingsLoaded;
    }

    _isLoadingSettings = true;
    try {
      if (_baseUrl.isEmpty) {
        print('ERROR: baseUrl이 설정되지 않았습니다');
        return false;
      }

      final url = Uri.parse('$_baseUrl/api/settings');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final platform = Platform.isIOS ? 'ios' : 'android';
        final ref = data['ref'] as Map<String, dynamic>?;
        
        if (ref != null && ref[platform] != null) {
          final platformRefs = ref[platform] as Map<String, dynamic>;
          _rewardedAdId = platformRefs['rewarded_ad'] as String?;
          _initialAdId = platformRefs['initial_ad'] as String?;
          
          print('DEBUG: 광고 설정 로드 완료');
          print('DEBUG: rewardedAdId: $_rewardedAdId');
          print('DEBUG: initialAdId: $_initialAdId');
          
          _settingsLoaded = true;
          
          // 광고 로드
          _loadRewardedAd();
          
          return true;
        } else {
          print('ERROR: 플랫폼별 광고 ID를 찾을 수 없습니다');
          return false;
        }
      } else {
        print('ERROR: 설정 로드 실패: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('ERROR: 설정 로드 중 오류: $e');
      return false;
    } finally {
      _isLoadingSettings = false;
    }
  }

  void _loadRewardedAd() {
    if (_rewardedAdId == null) {
      print('WARNING: rewardedAdId가 없어 광고를 로드할 수 없습니다');
      return;
    }

    RewardedAd.load(
      adUnitId: _rewardedAdId!,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          print('DEBUG: 보상형 광고 로드 완료');
          _rewardedAd = ad;
          _isRewardedAdReady = true;
          
          // 광고 이벤트 리스너 설정
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (RewardedAd ad) {
              print('DEBUG: 광고 닫힘');
              ad.dispose();
              _isRewardedAdReady = false;
              _loadRewardedAd(); // 다음 광고 로드
            },
            onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
              print('ERROR: 광고 표시 실패: $error');
              ad.dispose();
              _isRewardedAdReady = false;
              _loadRewardedAd(); // 다음 광고 로드
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('ERROR: 보상형 광고 로드 실패: $error');
          _isRewardedAdReady = false;
        },
      ),
    );
  }

  Future<void> showFullScreenAd({
    required VoidCallback onAdDismissed,
    VoidCallback? onAdFailedToShow,
  }) async {
    // 설정이 로드되지 않았으면 로드 시도
    if (!_settingsLoaded) {
      final loaded = await loadSettings();
      if (!loaded) {
        print('ERROR: 광고 설정을 로드할 수 없습니다');
        onAdFailedToShow?.call();
        return;
      }
    }

    // 광고가 준비되지 않았으면 로드 시도
    if (!_isRewardedAdReady) {
      _loadRewardedAd();
      // 광고 로드를 기다림 (최대 3초)
      int waitCount = 0;
      while (!_isRewardedAdReady && waitCount < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
    }

    if (_isRewardedAdReady && _rewardedAd != null) {
      // 콜백을 먼저 설정
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (RewardedAd ad) {
          print('DEBUG: 광고 닫힘 - 콜백 호출');
          onAdDismissed();
          ad.dispose();
          _isRewardedAdReady = false;
          _loadRewardedAd();
        },
        onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
          print('ERROR: 광고 표시 실패: $error');
          onAdFailedToShow?.call();
          ad.dispose();
          _isRewardedAdReady = false;
          _loadRewardedAd();
        },
      );
      
      // 광고 표시
      _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          print('DEBUG: 사용자가 보상 획득');
        },
      );
    } else {
      print('WARNING: 광고가 준비되지 않았습니다');
      onAdFailedToShow?.call();
    }
  }
}

