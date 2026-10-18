import { useState } from "react";
import { ActivityIndicator, Modal, StyleSheet, Text, View } from "react-native";
import { WebView } from "react-native-webview";

import { Button } from "@/ui/primitives";
import { colors, type } from "@/ui/theme";

// Cloudflare Turnstile in a web view anchored to tab-it.app (the widget's
// allowed hostname). Supabase rejects email-code requests without its token.

function widgetHtml(siteKey: string) {
  return `<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onLoad" async defer></script>
<style>html,body{margin:0;height:100%;background:transparent}body{display:flex;align-items:center;justify-content:center}</style>
</head><body><div id="widget"></div><script>
function post(event, payload){window.ReactNativeWebView.postMessage(JSON.stringify({event:event,payload:payload||""}));}
function onLoad(){turnstile.render("#widget",{sitekey:${JSON.stringify(siteKey)},
callback:function(t){post("token",t);},
"error-callback":function(c){post("error",String(c));return true;},
"expired-callback":function(){turnstile.reset("#widget");}});}
</script></body></html>`;
}

export function TurnstileSheet({
  siteKey,
  visible,
  onToken,
  onCancel,
}: {
  siteKey: string;
  visible: boolean;
  onToken: (token: string) => void;
  onCancel: () => void;
}) {
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onCancel}>
      <View style={styles.sheet}>
        <Text style={type.title}>Quick check</Text>
        <Text style={[type.small, { marginTop: 4 }]}>Confirming you're a person, not a bot.</Text>
        <View style={styles.widget}>
          {visible && (
            <WebView
              originWhitelist={["*"]}
              source={{ html: widgetHtml(siteKey), baseUrl: "https://tab-it.app" }}
              style={styles.web}
              onLoadEnd={() => setLoading(false)}
              onMessage={(event) => {
                try {
                  const { event: kind, payload } = JSON.parse(event.nativeEvent.data) as { event: string; payload: string };
                  if (kind === "token" && payload) onToken(payload);
                  else if (kind === "error") setError("The check didn't load. Try again.");
                } catch {
                  // Ignore unrelated messages.
                }
              }}
            />
          )}
          {loading && <ActivityIndicator style={StyleSheet.absoluteFill} color={colors.accent} />}
        </View>
        {error && <Text style={[type.small, { color: colors.danger, textAlign: "center" }]}>{error}</Text>}
        <Button title="Cancel" variant="secondary" onPress={onCancel} />
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  sheet: { flex: 1, backgroundColor: colors.bg, padding: 24, paddingTop: 32, alignItems: "stretch", gap: 16 },
  widget: { height: 120, justifyContent: "center" },
  web: { backgroundColor: "transparent" },
});
