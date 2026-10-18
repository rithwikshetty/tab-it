import * as AppleAuthentication from "expo-apple-authentication";
import { useEffect, useRef, useState, type ComponentRef } from "react";
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import {
  EMAIL_CODE_LENGTH,
  normalizeCode,
  sendEmailCode,
  signInWithApple,
  signInWithGoogle,
  signInWithLocalPassword,
  verifyEmailCode,
} from "@/data/auth";
import { TurnstileSheet } from "@/features/auth/turnstile";
import { config, PRIVACY_URL } from "@/lib/config";
import { haptics } from "@/ui/haptics";
import { Button, Field } from "@/ui/primitives";
import { colors, radius, type } from "@/ui/theme";
import * as WebBrowser from "expo-web-browser";

type Status = { kind: "idle" } | { kind: "busy"; what: "apple" | "google" | "send" | "verify" } | { kind: "sent"; message: string } | { kind: "error"; message: string };

export default function SignIn() {
  const [status, setStatus] = useState<Status>({ kind: "idle" });
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [pendingEmail, setPendingEmail] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [captchaFor, setCaptchaFor] = useState<{ email: string; message: string } | null>(null);
  const [appleAvailable, setAppleAvailable] = useState(false);
  const emailRef = useRef<ComponentRef<typeof TextInput>>(null);
  const busy = status.kind === "busy";

  useEffect(() => {
    if (Platform.OS === "ios") AppleAuthentication.isAvailableAsync().then(setAppleAvailable, () => setAppleAvailable(false));
  }, []);

  async function run(what: "apple" | "google" | "send" | "verify", work: () => Promise<unknown>) {
    setStatus({ kind: "busy", what });
    try {
      await work();
      setStatus((s) => (s.kind === "busy" ? { kind: "idle" } : s));
    } catch (error) {
      haptics.error();
      setStatus({ kind: "error", message: error instanceof Error ? error.message : "Something went wrong. Try again." });
    }
  }

  function requestCode(address: string, message: string) {
    if (config.turnstileSiteKey) setCaptchaFor({ email: address, message });
    else void send(address, message, null);
  }

  async function send(address: string, message: string, captcha: string | null) {
    await run("send", async () => {
      const sentTo = await sendEmailCode(address, name, captcha);
      setPendingEmail(sentTo);
      setCode("");
      setStatus({ kind: "sent", message });
    });
  }

  async function verify(value = code) {
    if (!pendingEmail || !normalizeCode(value)) return;
    await run("verify", () => verifyEmailCode(pendingEmail, value));
  }

  const canSend = name.trim().length > 0 && email.trim().length > 0 && !busy;

  return (
    <SafeAreaView style={styles.fill} edges={["top", "bottom"]}>
      <KeyboardAvoidingView style={styles.fill} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled" keyboardDismissMode="interactive">
          <View style={styles.brand}>
            <Text style={styles.wordmark}>tab-it</Text>
            <Text style={type.small}>keep track of shared expenses</Text>
          </View>

          <View style={styles.methods}>
            {appleAvailable && (
              <AppleAuthentication.AppleAuthenticationButton
                buttonType={AppleAuthentication.AppleAuthenticationButtonType.SIGN_IN}
                buttonStyle={AppleAuthentication.AppleAuthenticationButtonStyle.BLACK}
                cornerRadius={12}
                style={styles.apple}
                onPress={() => !busy && run("apple", signInWithApple)}
              />
            )}
            <Pressable
              accessibilityRole="button"
              disabled={busy}
              onPress={() => run("google", signInWithGoogle)}
              style={({ pressed }) => [styles.google, pressed && { opacity: 0.7 }]}
            >
              <Text style={styles.googleG}>G</Text>
              <Text style={styles.googleText}>Continue with Google</Text>
            </Pressable>

            <View style={styles.orRow}>
              <View style={styles.orLine} />
              <Text style={[type.small, { fontWeight: "500" }]}>or</Text>
              <View style={styles.orLine} />
            </View>

            {pendingEmail ? (
              <View style={{ gap: 10 }}>
                <Text style={[type.bodyStrong, { textAlign: "center" }]}>Enter your code</Text>
                <Text style={[type.small, { textAlign: "center" }]}>
                  We sent a {EMAIL_CODE_LENGTH}-digit code to {pendingEmail}.
                </Text>
                <Field
                  value={code}
                  onChangeText={(text) => {
                    const digits = text.replace(/\D/g, "").slice(0, EMAIL_CODE_LENGTH);
                    setCode(digits);
                    if (digits.length === EMAIL_CODE_LENGTH) void verify(digits);
                  }}
                  placeholder={`${EMAIL_CODE_LENGTH}-digit code`}
                  keyboardType="number-pad"
                  textContentType="oneTimeCode"
                  autoComplete="one-time-code"
                  autoFocus
                  style={styles.codeField}
                  accessibilityLabel="Verification code"
                />
                <Button
                  title="Verify code"
                  onPress={() => verify()}
                  loading={status.kind === "busy" && status.what === "verify"}
                  disabled={!normalizeCode(code) || busy}
                />
                <View style={styles.links}>
                  <Pressable disabled={busy} onPress={() => requestCode(pendingEmail, "New code sent.")} hitSlop={8}>
                    <Text style={styles.link}>Resend code</Text>
                  </Pressable>
                  <Pressable
                    disabled={busy}
                    hitSlop={8}
                    onPress={() => {
                      setPendingEmail(null);
                      setCode("");
                      setStatus({ kind: "idle" });
                    }}
                  >
                    <Text style={styles.link}>Change email</Text>
                  </Pressable>
                </View>
              </View>
            ) : (
              <View style={{ gap: 10 }}>
                <Field
                  value={name}
                  onChangeText={setName}
                  placeholder="Full name"
                  textContentType="name"
                  autoComplete="name"
                  returnKeyType="next"
                  onSubmitEditing={() => emailRef.current?.focus()}
                  accessibilityLabel="Full name"
                />
                <Field
                  ref={emailRef}
                  value={email}
                  onChangeText={setEmail}
                  placeholder="Email address"
                  textContentType="emailAddress"
                  autoComplete="email"
                  keyboardType="email-address"
                  autoCapitalize="none"
                  autoCorrect={false}
                  returnKeyType="send"
                  onSubmitEditing={() => canSend && requestCode(email, "Code sent. Check your email and enter it here.")}
                  accessibilityLabel="Email address"
                />
                <Button
                  title="Send email code"
                  onPress={() => requestCode(email, "Code sent. Check your email and enter it here.")}
                  loading={status.kind === "busy" && status.what === "send"}
                  disabled={!canSend}
                />
                <Text style={[type.small, { textAlign: "center" }]}>
                  We'll email you a {EMAIL_CODE_LENGTH}-digit code to sign in. No password needed.
                </Text>
              </View>
            )}

            {status.kind === "error" && <Text style={[styles.status, { color: colors.danger }]}>{status.message}</Text>}
            {status.kind === "sent" && <Text style={styles.status}>{status.message}</Text>}
            {status.kind === "busy" && (status.what === "apple" || status.what === "google") && (
              <Text style={styles.status}>Signing in…</Text>
            )}
          </View>

          {config.isLocalBackend && __DEV__ && <LocalSignIn onError={(m) => setStatus({ kind: "error", message: m })} />}

          <Pressable onPress={() => WebBrowser.openBrowserAsync(PRIVACY_URL)} hitSlop={8} style={{ alignSelf: "center" }}>
            <Text style={[type.small, { textDecorationLine: "underline" }]}>Privacy policy</Text>
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
      {config.turnstileSiteKey && (
        <TurnstileSheet
          siteKey={config.turnstileSiteKey}
          visible={captchaFor !== null}
          onCancel={() => setCaptchaFor(null)}
          onToken={(token) => {
            const request = captchaFor;
            setCaptchaFor(null);
            if (request) void send(request.email, request.message, token);
          }}
        />
      )}
    </SafeAreaView>
  );
}

/** Development only: one tap into a seeded account on the local Docker stack. */
function LocalSignIn({ onError }: { onError: (message: string) => void }) {
  const accounts = ["mock@tab.local", "alex@tab.local", "sam@tab.local"];
  return (
    <View style={styles.local}>
      <Text style={type.label}>Local stack</Text>
      <View style={{ flexDirection: "row", gap: 8, flexWrap: "wrap" }}>
        {accounts.map((account) => (
          <Pressable
            key={account}
            onPress={() => signInWithLocalPassword(account, "local-only-password").catch((e: Error) => onError(e.message))}
            style={({ pressed }) => [styles.localChip, pressed && { opacity: 0.6 }]}
          >
            <Text style={type.small}>{account.split("@")[0]}</Text>
          </Pressable>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1, backgroundColor: colors.bg },
  content: { flexGrow: 1, justifyContent: "center", paddingHorizontal: 24, paddingVertical: 40, gap: 40 },
  brand: { alignItems: "center", gap: 6 },
  wordmark: { fontSize: 44, fontWeight: "600", letterSpacing: -1.4, color: colors.text },
  methods: { gap: 12 },
  apple: { height: 52, width: "100%" },
  google: {
    height: 52,
    borderRadius: 12,
    backgroundColor: "#fff",
    borderWidth: 1,
    borderColor: colors.cardBorder,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 10,
  },
  googleG: { fontSize: 17, fontWeight: "700", color: colors.text },
  googleText: { fontSize: 16, fontWeight: "600", color: colors.text },
  orRow: { flexDirection: "row", alignItems: "center", gap: 12, paddingVertical: 4 },
  orLine: { flex: 1, height: 1, backgroundColor: colors.rowDivider },
  codeField: { textAlign: "center", fontSize: 22, letterSpacing: 6, fontVariant: ["tabular-nums"] },
  links: { flexDirection: "row", justifyContent: "center", gap: 24, paddingTop: 4 },
  link: { color: colors.accentStrong, fontWeight: "500", fontSize: 14 },
  status: { ...type.small, textAlign: "center", marginTop: 4 },
  local: { gap: 8, padding: 14, borderRadius: radius.card, backgroundColor: colors.surface2 },
  localChip: { paddingHorizontal: 12, paddingVertical: 8, borderRadius: radius.pill, backgroundColor: colors.surface },
});
