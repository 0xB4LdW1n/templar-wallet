import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:templar_wallet/theme/app_theme.dart';
import 'package:templar_wallet/theme/app_typography.dart';

/// Loads the wallet's vendored families before pixel comparison.
Future<void> loadTestFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final sans = FontLoader('IBMPlexSans')
    ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Bold.ttf'));
  final mono = FontLoader('IBMPlexMono')
    ..addFont(rootBundle.load('assets/fonts/IBMPlexMono-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/IBMPlexMono-Medium.ttf'));
  final nunito = FontLoader('Nunito')
    ..addFont(rootBundle.load('assets/fonts/Nunito-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Nunito-Bold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Nunito-ExtraBold.ttf'));
  await Future.wait([sans.load(), mono.load(), nunito.load()]);
}

/// Lets google_fonts resolve its asset cache before a golden captures frame 1.
Future<void> warmUpWalletFonts(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Column(
          children: [
            Text('Sans', style: AppTypography.body),
            Text('Medium', style: AppTypography.label),
            Text('Semibold', style: AppTypography.numeric),
            Text('Bold', style: AppTypography.navSection),
            Text('Display', style: AppTypography.pageTitle),
            Text('Display semibold', style: AppTypography.sectionTitle),
            Text('Display extrabold', style: AppTypography.displayTitle),
            Text('Mono', style: AppTypography.mono),
            Text('Mono medium', style: AppTypography.monoLarge),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Tear the warm-up navigator down; otherwise the next keyless MaterialApp
  // can reuse its route state instead of mounting the golden's home.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
