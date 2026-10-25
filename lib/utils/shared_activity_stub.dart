/// When any open tab of SAIS last saw the person do something. Nothing is
/// shared off the web, where there is only one window.
class SharedActivity {
  static DateTime? read(String owner) => null;

  static void write(String owner, DateTime when) {}
}
