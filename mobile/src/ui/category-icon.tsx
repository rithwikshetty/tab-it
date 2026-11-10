import { SvgXml } from "react-native-svg";

import { CATEGORY_ICON_XML } from "./category-icons";
import { categoryTones, colors } from "./theme";

export function categoryTone(categoryId: string | null | undefined): string {
  return (categoryId && categoryTones[categoryId]) || colors.textSecondary;
}

/** A category glyph: the category's Phosphor icon, or the tag for any other icon name. */
export function CategoryIcon({
  icon,
  categoryId,
  size = 26,
}: {
  icon: string | null | undefined;
  categoryId?: string | null;
  size?: number;
}) {
  const xml = (icon && CATEGORY_ICON_XML[icon]) || CATEGORY_ICON_XML.tag!;
  return <SvgXml xml={xml} width={size} height={size} color={categoryTone(categoryId)} />;
}
