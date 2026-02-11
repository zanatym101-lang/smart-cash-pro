class AppSession {
  static bool isAdmin = false;
  static String actorRole = 'user'; // user | admin | system
  static String actorName = 'مستخدم';

  static void enterUser() {
    isAdmin = false;
    actorRole = 'user';
    actorName = 'مستخدم';
  }

  static void enterAdmin() {
    isAdmin = true;
    actorRole = 'admin';
    actorName = 'أدمن';
  }
}

