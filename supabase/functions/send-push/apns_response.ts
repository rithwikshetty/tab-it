export type ApnsFailureClassification = "token-dead" | "environment-mismatch" | "other";

export function classifyApnsFailure(
  status: number,
  reason: string,
): ApnsFailureClassification {
  if (status === 410 || reason === "Unregistered") return "token-dead";
  if (reason === "BadDeviceToken") return "environment-mismatch";
  return "other";
}
