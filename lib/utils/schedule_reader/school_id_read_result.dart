/// Result of scanning a MarSU school ID photo or PDF on this device.
class SchoolIdReadResult {
  final bool ok;
  final String? studentId;
  final String? reason;

  const SchoolIdReadResult({required this.ok, this.studentId, this.reason});

  factory SchoolIdReadResult.fromJson(Map<String, dynamic> json) =>
      SchoolIdReadResult(
        ok: json['ok'] == true,
        studentId: json['studentId']?.toString(),
        reason: json['reason']?.toString(),
      );
}
