/// Money helper: amounts stored as *qirsh* (int).
/// 1 EGP = 100 qirsh.
class Money {
  static const int scale = 100;

  static int fromEgpDouble(double egp) => (egp * scale).round();
  static double toEgpDouble(int qirsh) => qirsh / scale;

  static String formatEgp(int qirsh) {
    final egp = toEgpDouble(qirsh);
    return egp.toStringAsFixed(2);
  }
}
