class ApiConfig {
  // ---------------------------------------------------------------------------
  // 1. আপনার ওয়েবসাইটটি যখন লাইভ ডোমেইনে থাকবে (যেমন Vercel এ Deploy করার পর):
  // static const String baseUrl = 'https://your-website-domain.com/api';
  //
  // 2. লোকাল পিসিতে Android Emulator দিয়ে টেস্ট করার জন্য (Next.js localhost:3000 এ চললে):
  static const String baseUrl = 'http://10.0.2.2:3000/api';
  // ---------------------------------------------------------------------------

  // Auth API Endpoints
  static const String loginEndpoint = '$baseUrl/auth/login';
  static const String registerEndpoint = '$baseUrl/auth/register';
  static const String forgotPasswordEndpoint = '$baseUrl/auth/forgot-password';
  static const String resetPasswordEndpoint = '$baseUrl/auth/reset-password';
}
