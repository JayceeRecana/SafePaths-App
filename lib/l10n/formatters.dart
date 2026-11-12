import '../utils/time_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'app_strings.dart';

String localizedClock(BuildContext context, DateTime time) => DateFormat(
  'h:mm a',
  Localizations.localeOf(context).toLanguageTag(),
).format(time.toLocal());

String localizedDateTime(BuildContext context, DateTime time) =>
    '${DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(time.toLocal())} ${localizedClock(context, time)}';

String localizedSubmissionDay(
  BuildContext context,
  DateTime submittedAt,
  DateTime now,
) {
  final key = TimeUtils.submissionDayKey(submittedAt, now);
  if (key == 'unknown') return tr(context, 'Submission time not recorded');
  if (key == 'future') return tr(context, 'Submission time needs confirmation');
  final day = TimeUtils.localDay(submittedAt), today = TimeUtils.localDay(now);
  if (day == today) return tr(context, 'Today');
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (day == yesterday) return tr(context, 'Yesterday');
  return DateFormat(
    day.year == today.year ? 'MMM d' : 'MMM d, y',
    Localizations.localeOf(context).toLanguageTag(),
  ).format(day);
}

Widget twelveHourPickerBuilder(BuildContext context, Widget? child) {
  final picker = MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
    child: child ?? const SizedBox.shrink(),
  );
  // Filipino Material defaults to 24 hours even when the device flag is false.
  // Override only its clock convention; keep the Filipino picker labels.
  return Localizations.localeOf(context).languageCode == 'fil'
      ? Localizations.override(
          context: context,
          delegates: const [_TwelveHourFilDelegate()],
          child: picker,
        )
      : picker;
}

class _TwelveHourFilDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _TwelveHourFilDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'fil';
  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    await GlobalMaterialLocalizations.delegate.load(locale);
    return _TwelveHourFilLocalizations();
  }

  @override
  bool shouldReload(_TwelveHourFilDelegate old) => false;
}

class _TwelveHourFilLocalizations extends MaterialLocalizationFil {
  _TwelveHourFilLocalizations()
    : super(
        fullYearFormat: DateFormat.y('fil'),
        compactDateFormat: DateFormat.yMd('fil'),
        shortDateFormat: DateFormat.yMMMd('fil'),
        mediumDateFormat: DateFormat.MMMEd('fil'),
        longDateFormat: DateFormat.yMMMMEEEEd('fil'),
        yearMonthFormat: DateFormat.yMMMM('fil'),
        shortMonthDayFormat: DateFormat.MMMd('fil'),
        decimalFormat: NumberFormat.decimalPattern('fil'),
        twoDigitZeroPaddedFormat: NumberFormat('00', 'fil'),
      );
  @override
  TimeOfDayFormat get timeOfDayFormatRaw => TimeOfDayFormat.h_colon_mm_space_a;
}

String localizedAge(BuildContext context, DateTime time, DateTime now) {
  final elapsed = now.difference(time);
  final fil = Localizations.localeOf(context).languageCode == 'fil';
  if (elapsed.isNegative) {
    return fil ? 'hindi kumpirmado ang oras' : 'time unconfirmed';
  }
  if (elapsed.inMinutes < 1) {
    return fil ? 'ngayon lang' : 'just now';
  }
  if (elapsed.inHours < 1) {
    return fil
        ? '${elapsed.inMinutes} minuto ang nakalipas'
        : '${elapsed.inMinutes} ${elapsed.inMinutes == 1 ? 'minute' : 'minutes'} ago';
  }
  if (elapsed.inDays < 1) {
    return fil
        ? '${elapsed.inHours} oras ang nakalipas'
        : '${elapsed.inHours} ${elapsed.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  return fil
      ? '${elapsed.inDays} araw ang nakalipas'
      : '${elapsed.inDays} ${elapsed.inDays == 1 ? 'day' : 'days'} ago';
}

String localizedReportStatus(BuildContext context, String status) =>
    tr(context, switch (status) {
      'pending' => 'Pending',
      'verified' => 'Verified',
      'under_review' => 'Under Review',
      'dismissed' => 'Dismissed',
      'resolved' => 'Resolved',
      'expired' => 'Expired',
      _ => 'Unconfirmed',
    });
