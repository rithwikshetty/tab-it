import { NativeTabs } from "expo-router/native-tabs";

import { useUnreadActivityCount } from "@/features/activity/use-unread";
import { colors } from "@/ui/theme";

export default function TabsLayout() {
  const unread = useUnreadActivityCount();
  return (
    <NativeTabs
      tintColor={colors.accentStrong}
      iconColor={colors.textSecondary}
      indicatorColor={colors.accentTint}
      backgroundColor={colors.bg}
      badgeBackgroundColor={colors.danger}
      labelStyle={{ fontSize: 11, fontWeight: "500" }}
    >
      <NativeTabs.Trigger name="friends">
        <NativeTabs.Trigger.Icon sf={{ default: "person.2", selected: "person.2.fill" }} md="group" />
        <NativeTabs.Trigger.Label>Friends</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="index">
        <NativeTabs.Trigger.Icon sf={{ default: "suitcase", selected: "suitcase.fill" }} md="luggage" />
        <NativeTabs.Trigger.Label>Trips</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="activity">
        <NativeTabs.Trigger.Icon sf={{ default: "bell", selected: "bell.fill" }} md="notifications" />
        <NativeTabs.Trigger.Label>Activity</NativeTabs.Trigger.Label>
        {unread > 0 && <NativeTabs.Trigger.Badge>{unread > 99 ? "99+" : String(unread)}</NativeTabs.Trigger.Badge>}
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="settings">
        <NativeTabs.Trigger.Icon sf={{ default: "gearshape", selected: "gearshape.fill" }} md="settings" />
        <NativeTabs.Trigger.Label>Settings</NativeTabs.Trigger.Label>
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
