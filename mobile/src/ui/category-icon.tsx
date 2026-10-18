import { View } from "react-native";
import { SvgXml } from "react-native-svg";

import { CATEGORY_ICON_XML } from "./category-icons";
import { categoryTones, colors } from "./theme";

export function categoryTone(categoryId: string | null | undefined): string {
  return (categoryId && categoryTones[categoryId]) || colors.textSecondary;
}

/**
 * A category glyph. Built-in categories use their Phosphor icon; a custom
 * category's icon is an emoji or short text drawn as-is.
 */
export function CategoryIcon({
  icon,
  categoryId,
  size = 26,
}: {
  icon: string | null | undefined;
  categoryId?: string | null;
  size?: number;
}) {
  const xml = icon ? CATEGORY_ICON_XML[icon] : undefined;
  const color = categoryTone(categoryId);
  if (xml) return <SvgXml xml={xml} width={size} height={size} color={color} />;
  return (
    <View style={{ width: size, height: size, alignItems: "center", justifyContent: "center" }}>
      <SvgXml xml={CATEGORY_ICON_XML.tag!} width={size} height={size} color={color} />
    </View>
  );
}
