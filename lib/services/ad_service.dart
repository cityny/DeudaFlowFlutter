import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Servicio simple para cargar y mostrar RewardedAds.
/// Comportamiento seguro: en plataformas no soportadas (web/desktop) devuelve true
/// para no bloquear la funcionalidad. Si el anuncio falla en cargar en el timeout
/// se permite la exportación y se notifica al usuario.
class AdService {
  AdService._private();
  static final AdService instance = AdService._private();

  // Flag simple para alternar entre IDs de prueba (Google) y producción.
  // Cambia a false cuando tengas tus Ad Unit IDs reales configurados.
  static const bool kUseTestAds = false;

  /// Tiempo máximo para cargar el anuncio (ms)
  static const int _loadTimeoutMs = 6000;
  static const int _baseBackoffSeconds = 2; // backoff inicial
  static const int _maxBackoffSeconds = 32; // límite de backoff

  bool _initialised = false;
  RewardedAd? _cachedRewardedAd; // instancia cacheada lista para mostrarse
  bool _isLoadingRewarded = false; // evita cargas simultáneas
  Completer<RewardedAd?>?
  _currentLoadCompleter; // para esperar una carga en curso
  int _consecutiveFailures = 0; // para cálculo de backoff
  Timer? _retryTimer; // reintento programado

  // --- Interstitial state ---
  InterstitialAd? _cachedInterstitialAd;
  bool _isLoadingInterstitial = false;
  Completer<InterstitialAd?>? _currentInterstitialLoadCompleter;
  int _consecutiveInterstitialFailures = 0;
  Timer? _interstitialRetryTimer;
  int _interstitialTotalLoads = 0;
  // ignore: unused_field
  int _interstitialSuccessfulLoads = 0;
  // ignore: unused_field
  int _interstitialFailedLoads = 0;
  DateTime? _lastInterstitialShownAt;
  final Random _random = Random();
  bool _isShowingAd = false; // evita mostrar varios full-screen a la vez

  // Métricas simples (solo debug)
  int _totalLoads = 0;
  int _successfulLoads = 0;
  int _failedLoads = 0;

  Future<void> initialize() async {
    if (_initialised) return;
    try {
      final requestConfig = RequestConfiguration(
        testDeviceIds: [
          '3C0F93D669F3396848E5965986B17370', //cambiar ultimo 0 por 6 para android Tecno 9 Pro
        ], // reemplaza con tu id
      );
      MobileAds.instance.updateRequestConfiguration(requestConfig);
      await MobileAds.instance.initialize();
      // Pre-cargar un Rewarded al arrancar (no esperamos resultado)
      unawaited(preloadRewarded());
      // También intentar precargar un Interstitial para inicio rápido
      unawaited(preloadInterstitial());
    } catch (_) {}
    _initialised = true;
  }

  String _interstitialAdUnitId(TargetPlatform platform) {
    if (kUseTestAds) {
      return platform == TargetPlatform.iOS
          ? 'ca-app-pub-3940256099942544/4411468910'
          : 'ca-app-pub-3940256099942544/1033173712';
    }
    return platform == TargetPlatform.iOS
        ? 'ca-app-pub-0202806937374735/REEMPLAZA_INTERSTITIAL'
        : 'ca-app-pub-0202806937374735/6175605381';
  }

  /// Devuelve el adUnitId (usar test IDs hasta sustituir por producción)
  String _rewardedAdUnitId(TargetPlatform platform) {
    if (kUseTestAds) {
      // IDs de PRUEBA oficiales de Google (no generan ingresos)
      return platform == TargetPlatform.iOS
          ? 'ca-app-pub-3940256099942544/1712485313'
          : 'ca-app-pub-3940256099942544/5224354917';
    }
    // IDs de PRODUCCIÓN (reemplaza por tus reales). iOS opcional si más adelante lo soportas.
    return platform == TargetPlatform.iOS
        ? 'ca-app-pub-0202806937374735/REEMPLAZA_IOS' // placeholder iOS
        : 'ca-app-pub-0202806937374735/6721248910'; // Rewarded real Android
  }

  /// Intenta cargar en background un Rewarded y dejarlo cacheado.
  /// No lanza excepciones y nunca bloquea la UI.
  Future<void> preloadRewarded() async {
    if (kIsWeb) return; // no aplica
    if (_isLoadingRewarded || _cachedRewardedAd != null) return;

    // Cancelar un retry programado si el usuario forzó una carga ahora
    _retryTimer?.cancel();

    _isLoadingRewarded = true;
    final platform = defaultTargetPlatform;
    if (!(platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS)) {
      _isLoadingRewarded = false;
      return;
    }

    _currentLoadCompleter = Completer<RewardedAd?>();
    _totalLoads++;
    final start = DateTime.now();
    if (kDebugMode) {
      debugPrint(
        '[AdService] Intentando precarga Rewarded ( intento #${_totalLoads} | fallos consecutivos: $_consecutiveFailures )',
      );
    }

    try {
      RewardedAd.load(
        adUnitId: _rewardedAdUnitId(platform),
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _cachedRewardedAd = ad;
            _isLoadingRewarded = false;
            _currentLoadCompleter?.complete(ad);
            _successfulLoads++;
            final ms = DateTime.now().difference(start).inMilliseconds;
            if (kDebugMode) {
              debugPrint(
                '[AdService] Rewarded precargado en ${ms}ms (exitos: $_successfulLoads / fallos: $_failedLoads). Reiniciando contador de backoff.',
              );
            }
            _consecutiveFailures = 0;
          },
          onAdFailedToLoad: (error) {
            _failedLoads++;
            final ms = DateTime.now().difference(start).inMilliseconds;
            if (kDebugMode) {
              debugPrint(
                '[AdService] preload falló: code=${error.code} domain=${error.domain} message="${error.message}" tras ${ms}ms',
              );
            }
            _isLoadingRewarded = false;
            _currentLoadCompleter?.complete(null);
            _handleLoadFailure();
          },
        ),
      );
    } catch (e) {
      if (kDebugMode)
        debugPrint('[AdService] Excepción al pre-cargar Rewarded: $e');
      _isLoadingRewarded = false;
      _currentLoadCompleter?.complete(null);
      _failedLoads++;
      _handleLoadFailure();
    }

    // Timeout de cortesía para no dejar futuros colgados
    unawaited(
      _currentLoadCompleter!.future.timeout(
        const Duration(milliseconds: _loadTimeoutMs),
        onTimeout: () {
          if (!_currentLoadCompleter!.isCompleted) {
            _isLoadingRewarded = false;
            _currentLoadCompleter!.complete(null);
            _failedLoads++;
            if (kDebugMode)
              debugPrint(
                '[AdService] Timeout de precarga ($_loadTimeoutMs ms).',
              );
            _handleLoadFailure();
          }
          return null;
        },
      ),
    );
  }

  /// Preloads an InterstitialAd and caches it for quick showing.
  Future<void> preloadInterstitial() async {
    if (kIsWeb) return;
    if (_isLoadingInterstitial || _cachedInterstitialAd != null) return;

    _interstitialRetryTimer?.cancel();
    _isLoadingInterstitial = true;
    final platform = defaultTargetPlatform;
    if (!(platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS)) {
      _isLoadingInterstitial = false;
      return;
    }

    _currentInterstitialLoadCompleter = Completer<InterstitialAd?>();
    _interstitialTotalLoads++;
    final start = DateTime.now();
    if (kDebugMode) {
      debugPrint(
        '[AdService] Intentando precarga Interstitial (intento #${_interstitialTotalLoads})',
      );
    }

    try {
      InterstitialAd.load(
        adUnitId: _interstitialAdUnitId(platform),
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _cachedInterstitialAd = ad;
            _isLoadingInterstitial = false;
            _currentInterstitialLoadCompleter?.complete(ad);
            _interstitialSuccessfulLoads++;
            final ms = DateTime.now().difference(start).inMilliseconds;
            if (kDebugMode)
              debugPrint('[AdService] Interstitial precargado en ${ms}ms');
            _consecutiveInterstitialFailures = 0;
          },
          onAdFailedToLoad: (error) {
            _interstitialFailedLoads++;
            final ms = DateTime.now().difference(start).inMilliseconds;
            if (kDebugMode) {
              debugPrint(
                '[AdService] Interstitial preload falló: ${error.message} tras ${ms}ms',
              );
            }
            _isLoadingInterstitial = false;
            _currentInterstitialLoadCompleter?.complete(null);
            _handleInterstitialLoadFailure();
          },
        ),
      );
    } catch (e) {
      if (kDebugMode)
        debugPrint('[AdService] Excepción al pre-cargar Interstitial: $e');
      _isLoadingInterstitial = false;
      _currentInterstitialLoadCompleter?.complete(null);
      _interstitialFailedLoads++;
      _handleInterstitialLoadFailure();
    }

    unawaited(
      _currentInterstitialLoadCompleter!.future.timeout(
        const Duration(milliseconds: _loadTimeoutMs),
        onTimeout: () {
          if (!_currentInterstitialLoadCompleter!.isCompleted) {
            _isLoadingInterstitial = false;
            _currentInterstitialLoadCompleter!.complete(null);
            _interstitialFailedLoads++;
            if (kDebugMode)
              debugPrint(
                '[AdService] Timeout de precarga Interstitial ($_loadTimeoutMs ms).',
              );
            _handleInterstitialLoadFailure();
          }
          return null;
        },
      ),
    );
  }

  void _handleInterstitialLoadFailure() {
    _consecutiveInterstitialFailures++;
    final raw =
        _baseBackoffSeconds * (1 << (_consecutiveInterstitialFailures - 1));
    final seconds = raw > _maxBackoffSeconds ? _maxBackoffSeconds : raw;
    if (kDebugMode)
      debugPrint(
        '[AdService] Programando reintento Interstitial en ${seconds}s (fallos: $_consecutiveInterstitialFailures)',
      );
    _interstitialRetryTimer?.cancel();
    _interstitialRetryTimer = Timer(Duration(seconds: seconds), () {
      if (_cachedInterstitialAd == null && !_isLoadingInterstitial) {
        preloadInterstitial();
      }
    });
  }

  /// Maneja un fallo de carga y programa reintento con backoff exponencial.
  void _handleLoadFailure() {
    _consecutiveFailures++;
    final seconds = _calculateBackoffSeconds();
    if (kDebugMode)
      debugPrint(
        '[AdService] Programando reintento en ${seconds}s (fallos consecutivos: $_consecutiveFailures).',
      );
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (_cachedRewardedAd == null && !_isLoadingRewarded) {
        preloadRewarded();
      }
    });
  }

  int _calculateBackoffSeconds() {
    final raw = _baseBackoffSeconds * (1 << (_consecutiveFailures - 1));
    if (raw > _maxBackoffSeconds) return _maxBackoffSeconds;
    return raw;
  }

  /// Permite forzar un recálculo inmediato (por ejemplo si el usuario abre un modal que pronto necesitará el anuncio).
  Future<void> forceWarmup() async {
    if (_cachedRewardedAd != null || _isLoadingRewarded) return;
    preloadRewarded();
  }

  /// Shows a rewarded ad. Returns true when the user earned the reward OR
  /// when ads are not supported on the current platform. Returns false when
  /// the ad was shown but user didn't earn the reward.
  Future<bool> showRewardedAd(BuildContext context) async {
    // Don't attempt to show ads on web or unsupported platforms
    if (kIsWeb) return true;
    final platform = Theme.of(context).platform;
    if (!(platform == TargetPlatform.android ||
        platform == TargetPlatform.iOS)) {
      return true;
    }

    await initialize();
    // Si ya hay uno cacheado listo, úsalo; si no, intenta cargar (espera limitada).
    if (_cachedRewardedAd == null) {
      // Disparar carga si no está en curso
      await preloadRewarded();
      // Si se está cargando, esperar hasta timeout o resultado
      if (_currentLoadCompleter != null &&
          !_currentLoadCompleter!.isCompleted) {
        try {
          await _currentLoadCompleter!.future.timeout(
            const Duration(milliseconds: _loadTimeoutMs),
            onTimeout: () => null,
          );
        } catch (_) {}
      }
    }

    final ad = _cachedRewardedAd;
    if (ad == null) {
      // No se pudo conseguir anuncio → permitir acción
      if (kDebugMode)
        debugPrint(
          '[AdService] No hay Rewarded listo: se permite acción sin anuncio.',
        );
      return true;
    }

    final resultCompleter = Completer<bool>();
    bool rewarded = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(rewarded);
        }
        ad.dispose();
        _cachedRewardedAd = null;
        // Pre-cargar el siguiente inmediatamente
        unawaited(preloadRewarded());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        if (!resultCompleter.isCompleted) {
          // Permitimos la acción si falla al mostrar
          resultCompleter.complete(true);
        }
        ad.dispose();
        _cachedRewardedAd = null;
        unawaited(preloadRewarded());
      },
    );

    try {
      ad.show(
        onUserEarnedReward: (adWithoutView, rewardItem) {
          rewarded = true;
          if (!resultCompleter.isCompleted) {
            resultCompleter.complete(true);
          }
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[AdService] Error al mostrar Rewarded: $e');
      if (!resultCompleter.isCompleted) resultCompleter.complete(true);
      _cachedRewardedAd = null;
      unawaited(preloadRewarded());
    }

    return resultCompleter.future.timeout(
      const Duration(milliseconds: _loadTimeoutMs + 4000),
      onTimeout: () {
        if (!resultCompleter.isCompleted) resultCompleter.complete(true);
        return true;
      },
    );
  }

  /// Shows an interstitial if available. Returns true always (non-blocking UX);
  /// the method will not show an interstitial if one is already showing or if
  /// platform isn't supported.
  Future<bool> showInterstitial({BuildContext? context}) async {
    if (kIsWeb) return true;
    final platform = context != null
        ? Theme.of(context).platform
        : defaultTargetPlatform;
    if (!(platform == TargetPlatform.android || platform == TargetPlatform.iOS))
      return true;

    await initialize();
    if (_isShowingAd) return true;

    if (_cachedInterstitialAd == null) {
      await preloadInterstitial();
      if (_currentInterstitialLoadCompleter != null &&
          !_currentInterstitialLoadCompleter!.isCompleted) {
        try {
          await _currentInterstitialLoadCompleter!.future.timeout(
            const Duration(milliseconds: _loadTimeoutMs),
          );
        } catch (_) {}
      }
    }

    final ad = _cachedInterstitialAd;
    if (ad == null) {
      debugPrint('[AdService] No hay Interstitial listo.');
      return true;
    }

    final completer = Completer<bool>();
    _isShowingAd = true;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _cachedInterstitialAd = null;
        _isShowingAd = false;
        _lastInterstitialShownAt = DateTime.now();
        unawaited(preloadInterstitial());
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _cachedInterstitialAd = null;
        _isShowingAd = false;
        unawaited(preloadInterstitial());
        if (!completer.isCompleted) completer.complete(true);
      },
    );

    try {
      ad.show();
    } catch (e) {
      debugPrint('[AdService] Error al mostrar Interstitial: $e');
      _cachedInterstitialAd = null;
      _isShowingAd = false;
      unawaited(preloadInterstitial());
      if (!completer.isCompleted) completer.complete(true);
    }

    // timeout guard
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        if (!completer.isCompleted) completer.complete(true);
        _isShowingAd = false;
        return true;
      },
    );
  }

  /// Call this from navigation events to maybe show an interstitial.
  /// Default: 30% chance, minInterval 2 minutes between interstitials.
  Future<bool> maybeShowInterstitialOnNavigation({
    double probability = 0.3,
    Duration minInterval = const Duration(minutes: 6),
  }) async {
    // Basic guards
    if (_isShowingAd) return false;
    final now = DateTime.now();
    if (_lastInterstitialShownAt != null &&
        now.difference(_lastInterstitialShownAt!) < minInterval) {
      return false;
    }
    final roll = _random.nextDouble();
    if (roll > probability) return false;

    final shown = await showInterstitial();
    return shown;
  }
}
