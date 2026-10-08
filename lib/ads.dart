import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdsController extends ChangeNotifier {
  bool ready = false, privacyRequired = false, _closed = false;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  String get bannerId => kReleaseMode
      ? const String.fromEnvironment('ADMOB_BANNER_ID')
      : (defaultTargetPlatform == TargetPlatform.iOS
            ? 'ca-app-pub-3940256099942544/2934735716'
            : 'ca-app-pub-3940256099942544/6300978111');
  Future<void> initialize() async {
    if (!supported) return;
    try {
      final update = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (!update.isCompleted) update.complete();
        },
        (_) {
          if (!update.isCompleted) update.complete();
        },
      );
      await update.future.timeout(const Duration(seconds: 12));
      final form = Completer<void>();
      await ConsentForm.loadAndShowConsentFormIfRequired((_) {
        if (!form.isCompleted) form.complete();
      });
      await form.future.timeout(const Duration(seconds: 30));
      privacyRequired =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      if (_closed) return;
      notifyListeners();
      if (!await ConsentInformation.instance.canRequestAds() || _closed) return;
      await MobileAds.instance.initialize();
      if (_closed) return;
      ready = true;
      notifyListeners();
    } catch (_) {
      /* Offline consent or ads must not stop outfit recommendations. */
    }
  }

  Future<void> privacyOptions() async {
    if (!supported || !privacyRequired) return;
    await ConsentForm.showPrivacyOptionsForm((_) {});
    if (!await ConsentInformation.instance.canRequestAds()) {
      ready = false;
      notifyListeners();
    } else if (!ready) {
      await MobileAds.instance.initialize();
      if (_closed) return;
      ready = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}

class SetupBanner extends StatefulWidget {
  const SetupBanner({super.key, required this.ads});
  final AdsController ads;
  @override
  State<SetupBanner> createState() => _SetupBannerState();
}

class _SetupBannerState extends State<SetupBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    widget.ads.addListener(_update);
    _update();
  }

  void _update() {
    if (!widget.ads.ready) {
      _ad?.dispose();
      _ad = null;
      if (mounted) setState(() => _loaded = false);
      return;
    }
    if (_ad != null || widget.ads.bannerId.isEmpty) return;
    _ad = BannerAd(
      adUnitId: widget.ads.bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    widget.ads.removeListener(_update);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_loaded || _ad == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: SizedBox(
              width: _ad!.size.width.toDouble(),
              height: _ad!.size.height.toDouble(),
              child: AdWidget(ad: _ad!),
            ),
          ),
        );
}
