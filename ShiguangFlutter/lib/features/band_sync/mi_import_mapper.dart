// ShiguangFlutter/lib/features/band_sync/mi_import_mapper.dart
// 小米云端运动记录 → 站内运动记录候选（纯函数层，禁止 import flutter）。
//
// 口径（与 HC 版 mapper 的差异点）：
// - 卡路里优先用云端 calories（手环实测的**运动消耗**，不含基础代谢），
//   缺失时才回落站内 MET/距离公式；
// - rope_skipping 站内是次数型（rep），云端没有次数，一律跳过不猜；
// - 距离型缺距离时按典型配速估算并打标。
import 'package:shiguang_flutter/data/mi_cloud_client.dart';
import 'package:shiguang_flutter/domain/constants.dart';
import 'package:shiguang_flutter/domain/exercise.dart';

enum MiSkipReason {
  invalidRange,
  tooShort,
  zeroAmount,
  zeroKcal,
  unsupportedActivity,
  duplicate,
  alreadyImported,
}

class MiSkippedWorkout {
  const MiSkippedWorkout({required this.workout, required this.reason});
  final MiWorkout workout;
  final MiSkipReason reason;
}

class MiImportCandidate {
  const MiImportCandidate({
    required this.payload,
    required this.externalId,
    required this.start,
    required this.end,
    required this.estimatedDistance,
    this.sourceKcal,
  });

  /// 与 POST /diet/exercises 同形七键。
  final Map<String, dynamic> payload;

  /// 去重键：`mi:<sid>_<key>_<time>`。
  final String externalId;
  final DateTime start;
  final DateTime end;
  final bool estimatedDistance;

  /// 云端 calories 原值（参考用；payload.kcal 优先取它）。
  final double? sourceKcal;
}

class MiImportResult {
  const MiImportResult({required this.candidates, required this.skipped});
  final List<MiImportCandidate> candidates;
  final List<MiSkippedWorkout> skipped;
  bool get isEmpty => candidates.isEmpty;
}

/// 小米 sport key → 站内运动库 key。只收语义明确的映射。
const _activityKeyMap = <String, String>{
  'outdoor_running': 'run',
  'indoor_running': 'run',
  'running': 'run',
  'treadmill': 'run',
  'outdoor_walking': 'walk',
  'indoor_walking': 'walk',
  'walking': 'walk',
  'hiking': 'walk',
  'outdoor_cycling': 'cycle',
  'indoor_cycling': 'cycle',
  'cycling': 'cycle',
  'swimming': 'swim',
  'pool_swimming': 'swim',
  'open_water_swimming': 'swim',
  'strength_training': 'strength',
  'free_training': 'strength',
  'weightlifting': 'strength',
  'yoga': 'yoga',
  'pilates': 'yoga',
  'hiit': 'hiit',
  'high_intensity_interval_training': 'hiit',
  'basketball': 'ball',
  'football': 'ball',
  'soccer': 'ball',
  'badminton': 'ball',
  'table_tennis': 'ball',
  'tennis': 'ball',
  'volleyball': 'ball',
};

const _assumedSpeedKmh = <String, double>{
  'run': 8.0,
  'walk': 5.0,
  'cycle': 15.0,
};

final _libByKey = <String, Exercise>{
  for (final e in exerciseLib) e.key: e,
};

MiImportResult mapMiWorkouts({
  required List<MiWorkout> workouts,
  required num? weightKg,
  Set<String> importedIds = const <String>{},
  Set<String> importedSignatures = const <String>{},
}) {
  final candidates = <MiImportCandidate>[];
  final skipped = <MiSkippedWorkout>[];
  final seenIds = <String>{};
  final seenSignatures = <String>{};

  final ordered = List<MiWorkout>.of(workouts)
    ..sort((a, b) => a.startAt.compareTo(b.startAt));

  for (final w in ordered) {
    void skip(MiSkipReason reason) =>
        skipped.add(MiSkippedWorkout(workout: w, reason: reason));

    final externalId = 'mi:${w.workoutId}';
    if (importedIds.contains(externalId)) {
      skip(MiSkipReason.alreadyImported);
      continue;
    }
    if (!w.endAt.isAfter(w.startAt)) {
      skip(MiSkipReason.invalidRange);
      continue;
    }
    if (!seenIds.add(externalId)) {
      skip(MiSkipReason.duplicate);
      continue;
    }

    final key = _activityKeyMap[w.activityType];
    final lib = key == null ? null : _libByKey[key];
    if (lib == null) {
      skip(MiSkipReason.unsupportedActivity);
      continue;
    }

    final num amount;
    var estimatedDistance = false;
    if (lib.unit == 'km') {
      final dist = w.distanceM;
      if (dist != null && dist > 0) {
        amount = roundTo2(dist / 1000);
      } else {
        final speed = _assumedSpeedKmh[lib.key] ?? 5.0;
        final hours = w.durationMinutes / 60;
        amount = roundTo2(hours * speed);
        estimatedDistance = true;
      }
      if (amount <= 0) {
        skip(MiSkipReason.zeroAmount);
        continue;
      }
    } else {
      if (w.durationMinutes <= 0) {
        skip(MiSkipReason.tooShort);
        continue;
      }
      amount = w.durationMinutes;
    }

    final measured = w.caloriesKcal;
    final int kcal;
    if (measured != null && measured > 0) {
      kcal = measured.round();
    } else {
      kcal = exerciseKcalOf(lib, amount, weightKg);
    }
    if (kcal <= 0) {
      skip(MiSkipReason.zeroKcal);
      continue;
    }

    // 云端内容签名（date|key|amount|kcal）：老数据没有 externalId 时兜底去重。
    final date = localDateOf(w.startAt);
    final cloudSignature = '$date|${lib.key}|$amount|$kcal';
    if (importedSignatures.contains(cloudSignature)) {
      skip(MiSkipReason.alreadyImported);
      continue;
    }

    final signature =
        '${lib.key}|${w.startAt.millisecondsSinceEpoch}|${w.endAt.millisecondsSinceEpoch}';
    if (!seenSignatures.add(signature)) {
      skip(MiSkipReason.duplicate);
      continue;
    }

    candidates.add(MiImportCandidate(
      payload: <String, dynamic>{
        'date': localDateOf(w.startAt),
        'key': lib.key,
        'name': lib.name,
        'emoji': lib.emoji,
        'amount': amount,
        'unit': lib.unit,
        'kcal': kcal,
      },
      externalId: externalId,
      start: w.startAt,
      end: w.endAt,
      estimatedDistance: estimatedDistance,
      sourceKcal: measured,
    ));
  }

  return MiImportResult(candidates: candidates, skipped: skipped);
}

String localDateOf(DateTime t) {
  final d = t.toLocal();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

double roundTo2(num v) => (v * 100).round() / 100;
