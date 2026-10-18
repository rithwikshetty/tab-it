import { MenuView } from "@react-native-menu/menu";
import { StyleSheet, Text, View } from "react-native";

import { Avatar } from "@/ui/avatar";
import { Icon } from "@/ui/primitives";
import { colors, radius } from "@/ui/theme";

export interface SelectablePerson {
  id: string;
  name: string;
  avatarName: string;
  email?: string;
  pending?: boolean;
}

/** A pill that opens a native menu of people. */
export function PersonSelect({
  people,
  value,
  onChange,
  label,
}: {
  people: SelectablePerson[];
  value: string | null;
  onChange: (id: string) => void;
  label: string;
}) {
  const current = people.find((p) => p.id === value);
  return (
    <MenuView
      title={label}
      actions={people.map((p) => ({ id: p.id, title: p.name, state: p.id === value ? "on" : "off" }))}
      onPressAction={({ nativeEvent }) => onChange(nativeEvent.event)}
    >
      <View style={styles.pill} accessible accessibilityRole="button" accessibilityLabel={`${label}: ${current?.name ?? "choose"}`}>
        {current && (
          <Avatar
            person={{ id: current.id, name: current.avatarName, email: current.email, pending: current.pending }}
            size={24}
            ring={0}
          />
        )}
        <Text style={styles.text} numberOfLines={1}>
          {current?.name ?? "Choose"}
        </Text>
        <Icon name="chevron-down" size={13} color={colors.textSecondary} />
      </View>
    </MenuView>
  );
}

const styles = StyleSheet.create({
  pill: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    paddingLeft: 6,
    paddingRight: 12,
    paddingVertical: 6,
    borderRadius: radius.pill,
    backgroundColor: colors.surface2,
    maxWidth: 200,
  },
  text: { fontSize: 15, fontWeight: "500", color: colors.text, flexShrink: 1 },
});
