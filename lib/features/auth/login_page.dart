import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/glo_theme.dart';
import '../../core/widgets/glo_widgets.dart';
import '../home/shell_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool obscure = true;
  String? error;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (username.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your GLO corporate username and password.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ApiService.login(username.text.trim(), password.text);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ShellPage()));
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          Positioned(top: -150, right: -120, child: Container(width: 360, height: 360, decoration: const BoxDecoration(shape: BoxShape.circle, color: GloColors.lightGreen))),
          Positioned(bottom: -170, left: -150, child: Container(width: 350, height: 350, decoration: const BoxDecoration(shape: BoxShape.circle, color: GloColors.mint))),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 38, 28, 28),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Align(alignment: Alignment.centerLeft, child: GloLogo(size: 78)),
                    const SizedBox(height: 30),
                    const Text('Employee Attendance', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -.8, color: GloColors.ink)),
                    const Text('Management System', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: GloColors.darkGreen)),
                    const SizedBox(height: 13),
                    const Text('Secure attendance for Globacom employees: verified by identity, device and location.', style: TextStyle(fontSize: 14, height: 1.5, color: GloColors.muted)),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: GloColors.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Container(width: 42, height: 42, decoration: BoxDecoration(color: GloColors.lightGreen, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.corporate_fare_rounded, color: GloColors.darkGreen)),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('GLO Corporate Account', style: TextStyle(fontWeight: FontWeight.w800)),
                              SizedBox(height: 2),
                              Text('Sign in with your network account', style: TextStyle(fontSize: 12, color: GloColors.muted)),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        TextField(
                          controller: username,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.none,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Corporate username', prefixIcon: Icon(Icons.person_outline_rounded)),
                        ),
                        const SizedBox(height: 13),
                        TextField(
                          controller: password,
                          obscureText: obscure,
                          onSubmitted: (_) => busy ? null : signIn(),
                          decoration: InputDecoration(
                            labelText: 'Corporate password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => obscure = !obscure),
                              icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            ),
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(error!, style: const TextStyle(color: GloColors.red, fontSize: 13)),
                        ],
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed: busy ? null : signIn,
                          icon: busy
                              ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.login_rounded),
                          label: Text(busy ? 'Authenticating…' : 'Sign in securely'),
                        ),
                        const SizedBox(height: 15),
                        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.shield_outlined, size: 16, color: GloColors.primary),
                          SizedBox(width: 7),
                          Text('Checked against GLO corporate identity', style: TextStyle(fontSize: 11.5, color: GloColors.muted)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 25),
                    const Row(children: [
                      Icon(Icons.lock_outline_rounded, size: 15, color: GloColors.muted),
                      SizedBox(width: 7),
                      Expanded(child: Text('Your password is checked against the Globacom corporate directory and is never stored by EAMS.', style: TextStyle(fontSize: 11.5, color: GloColors.muted, height: 1.4))),
                    ]),
                    const SizedBox(height: 28),
                    const Center(child: Text('Globacom Limited  •  GLO EAMS', style: TextStyle(fontSize: 11, color: GloColors.muted))),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
}
