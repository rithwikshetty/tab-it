import { MenuView, type MenuAction } from "@react-native-menu/menu";
import { Platform, View } from "react-native";

import { Icon } from "./primitives";
import { colors } from "./theme";

export interface MenuItem {
  id: string;
  title: string;
  /** SF Symbol name, shown on iOS. */
  symbol?: string;
  destructive?: boolean;
  disabled?: boolean;
  onPress: () => void;
}

/** A native menu (UIMenu on iOS, a popup menu on Android) behind a "more" button. */
export function MoreMenu({ items, label = "More actions" }: { items: MenuItem[]; label?: string }) {
  const actions: MenuAction[] = items.map((item) => ({
    id: item.id,
    title: item.title,
    image: Platform.OS === "ios" ? item.symbol : undefined,
    imageColor: item.destructive ? colors.danger : colors.text,
    attributes: { destructive: item.destructive, disabled: item.disabled },
  }));
  return (
    <MenuView
      actions={actions}
      isAnchoredToRight
      onPressAction={({ nativeEvent }) => items.find((i) => i.id === nativeEvent.event)?.onPress()}
    >
      <View accessible accessibilityRole="button" accessibilityLabel={label} style={{ padding: 6 }} hitSlop={8}>
        <Icon name="ellipsis-horizontal" size={22} color={colors.accentStrong} />
      </View>
    </MenuView>
  );
}
