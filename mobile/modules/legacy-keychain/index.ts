import { requireOptionalNativeModule } from "expo";
import { Platform } from "react-native";

interface LegacyKeychain {
  readLegacySession(service: string, account: string): Promise<string | null>;
  deleteLegacySession(service: string, account: string): Promise<boolean>;
}

export async function readLegacySession(service: string, account: string): Promise<string | null> {
  if (Platform.OS !== "ios") return null;
  return requireOptionalNativeModule<LegacyKeychain>("LegacyKeychain")?.readLegacySession(service, account) ?? null;
}

export async function deleteLegacySession(service: string, account: string): Promise<boolean> {
  if (Platform.OS !== "ios") return false;
  return requireOptionalNativeModule<LegacyKeychain>("LegacyKeychain")?.deleteLegacySession(service, account) ?? false;
}
