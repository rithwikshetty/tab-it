import DateTimePicker, { DateTimePickerAndroid } from "@react-native-community/datetimepicker";
import { Platform, Pressable, StyleSheet, Text } from "react-native";

import { dayOf, dayToDate, longDay } from "@/lib/dates";
import { Row } from "@/ui/primitives";
import { colors } from "@/ui/theme";

/** A calendar-day row: native compact picker on iOS, the system dialog on Android. */
export function DateField({ label, day, onChange }: { label: string; day: string; onChange: (day: string) => void }) {
  if (Platform.OS === "ios") {
    return (
      <Row
        title={label}
        right={
          <DateTimePicker
            value={dayToDate(day)}
            mode="date"
            display="compact"
            accentColor={colors.accentStrong}
            onValueChange={(_e, date) => onChange(dayOf(date))}
          />
        }
      />
    );
  }
  return (
    <Row
      title={label}
      right={
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`${label}, ${longDay(day)}. Change`}
          onPress={() =>
            DateTimePickerAndroid.open({
              value: dayToDate(day),
              mode: "date",
              onValueChange: (_event, date) => onChange(dayOf(date)),
            })
          }
          style={styles.chip}
        >
          <Text style={styles.chipText}>{longDay(day)}</Text>
        </Pressable>
      }
    />
  );
}

const styles = StyleSheet.create({
  chip: { paddingHorizontal: 12, paddingVertical: 7, borderRadius: 8, backgroundColor: colors.surface2 },
  chipText: { fontSize: 15, color: colors.text },
});
