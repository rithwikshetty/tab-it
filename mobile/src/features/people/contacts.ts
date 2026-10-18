import { Contact } from "expo-contacts";
import { Alert } from "react-native";

import { isValidEmail, normalizedEmail } from "@/domain";

/** Opens the system contact picker and returns the chosen person's email. */
export async function pickContactEmail(): Promise<{ email: string; displayName: string } | null> {
  const contact = await Contact.presentPicker();
  if (!contact) return null;
  const [emails, fullName] = await Promise.all([contact.getEmails(), contact.getFullName().catch(() => "")]);
  const addresses = [...new Set(emails.map((e) => normalizedEmail(e.address ?? "")).filter(isValidEmail))];
  const displayName = fullName.trim() || addresses[0]?.split("@")[0] || "";
  if (addresses.length === 0) {
    Alert.alert("No email address", `${displayName || "This contact"} has no email address saved. Type it in instead.`);
    return null;
  }
  if (addresses.length === 1) return { email: addresses[0]!, displayName };
  return new Promise((resolve) => {
    Alert.alert(
      "Which email?",
      `${displayName} has more than one. They join by signing in with the one you pick.`,
      [
        ...addresses.slice(0, 4).map((email) => ({ text: email, onPress: () => resolve({ email, displayName }) })),
        { text: "Cancel", style: "cancel" as const, onPress: () => resolve(null) },
      ],
      { cancelable: true, onDismiss: () => resolve(null) },
    );
  });
}
