import { useRef, type ReactNode } from "react";
import { Pressable, StyleSheet, Text } from "react-native";
import ReanimatedSwipeable, { type SwipeableMethods } from "react-native-gesture-handler/ReanimatedSwipeable";

import { haptics } from "./haptics";
import { Icon } from "./primitives";
import { colors } from "./theme";

/** A row that reveals a delete action when swiped left. */
export function SwipeToDelete({ children, onDelete, label = "Delete" }: { children: ReactNode; onDelete: () => void; label?: string }) {
  const ref = useRef<SwipeableMethods>(null);
  return (
    <ReanimatedSwipeable
      ref={ref}
      friction={2}
      rightThreshold={40}
      overshootRight={false}
      onSwipeableWillOpen={() => haptics.light()}
      renderRightActions={() => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={label}
          style={styles.action}
          onPress={() => {
            ref.current?.close();
            onDelete();
          }}
        >
          <Icon name="trash-outline" size={20} color="#fff" />
          <Text style={styles.label}>{label}</Text>
        </Pressable>
      )}
    >
      {children}
    </ReanimatedSwipeable>
  );
}

const styles = StyleSheet.create({
  action: { width: 88, backgroundColor: colors.danger, alignItems: "center", justifyContent: "center", gap: 2 },
  label: { color: "#fff", fontSize: 12, fontWeight: "600" },
});
