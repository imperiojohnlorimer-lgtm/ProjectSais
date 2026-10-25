# SAIS Flutter Design System

## Overview
This document outlines the design system used in the projectsais Flutter application, which has been updated to match the siasprototype (React) design.

## Color Palette

### Primary Colors
- **Maroon (Primary)**: `#8B1C3E` - Main brand color
- **Maroon Dark**: `#722D43` - Used for gradients and emphasis
- **Maroon Light**: `#C38795` - Lighter variant for secondary uses
- **Gold (Accent)**: `#FFD700` - Accent color for highlights

### Maroon Palette
| Shade | Hex | Use |
|-------|-----|-----|
| 50 | #F5EDED | Background |
| 100 | #EBDDC | Soft backgrounds |
| 200 | #D7AFB8 | Borders |
| (Primary) | #8B1C3E | Main brand |
| Dark | #722D43 | Gradients |
| Light | #C38795 | Secondary |

### Gold Palette
| Shade | Hex | Use |
|-------|-----|-----|
| 50 | #FFFEF0 | Background |
| 100 | #FFFCE1 | Soft backgrounds |
| 300 | #FFF5A3 | Borders |
| (Primary) | #FFD700 | Main accent |

### Neutral Colors
- **Slate 50**: `#F8FAFC` - Light background
- **Slate 100**: `#F1F5F9` - Slightly darker background
- **Slate 200**: `#E2E8F0` - Borders
- **Slate 300**: `#CBD5E1` - Disabled text
- **Slate 400**: `#94A3B8` - Secondary text
- **Slate 500**: `#64748B` - Tertiary text
- **Slate 600**: `#475569` - Body text
- **Slate 700**: `#334155` - Strong text
- **Slate 800**: `#1E293B` - Heading text
- **Slate 900**: `#0F172A` - Darkest text

### Status Colors
- **Emerald 500**: `#10B981` - Success/Active
- **Red 500**: `#EF4444` - Error/Danger
- **Amber 500**: `#F59E0B` - Warning
- **Blue 500**: `#3B82F6` - Info

## Typography

### Font Family
- **Primary**: Inter (from google_fonts)
- **Weights**: 400 (Regular), 500 (Medium), 600 (Semibold), 700 (Bold), 800 (Extra Bold)
- **Letter Spacing**: 0-0.8px for hierarchy

### Text Styles

| Style | Size | Weight | Color | Letter Spacing |
|-------|------|--------|-------|-----------------|
| Heading 1 | 28-32px | 700-800 | Slate 900 | -0.5 to -1.68px |
| Heading 2 | 24px | 700 | Slate 900 | -0.24px |
| Body Large | 16px | 600 | Slate 600 | 0.3px |
| Body | 14px | 500-600 | Slate 700 | 0.3px |
| Label | 12px | 600 | Slate 700 | 0.5-0.8px |
| Small | 11px | 500 | Slate 500 | 0.3px |
| Tiny | 10px | 600 | Slate 400 | 0.5px |

## Component Styles

### Buttons
All buttons use border radius of 12px with proper padding.

#### ElevatedButton (Primary)
- Background: Gradient (Maroon → Maroon Dark)
- Text: White, weight 600, size 14px
- Padding: 24px horizontal, 14px vertical
- Elevation: 2
- Shadow: Maroon with 30% opacity

#### OutlinedButton (Secondary)
- Border: Maroon, 1.5px
- Text: Maroon, weight 600
- Padding: 24px horizontal, 14px vertical
- Radius: 12px

#### TextButton (Tertiary)
- Text: Maroon, weight 600
- No background or border
- Used for navigation

### Cards
- Border Radius: 16px
- Border: 1px, Slate 200
- Elevation: 1
- Shadow: Subtle (Black 5% opacity)
- Background: White
- Padding: Varies by card type

### Input Fields
- Border Radius: 12px
- Border: 1.5px, Slate 300 (enabled), Maroon 2px (focused)
- Fill Color: Slate 50
- Padding: 16px horizontal, 14px vertical
- Focus Color: Maroon with ring effect
- Error Border: Red 500

### Headers & AppBar
- Background: White
- Elevation: 2
- Bottom Border: 3px gradient (Gold)
- Title: Gradient text (Maroon → Maroon Dark)
- Icon Colors: Slate 700, Maroon (active)

### Sidebar Navigation
- Background: White
- Border: 2px Gold bottom (header section)
- Active Item: 
  - Gradient (Maroon → Maroon Dark)
  - Left border: 4px Gold
  - Shadow: Maroon 20% opacity
- Inactive Item:
  - Background: Transparent
  - Text: Slate 700
  - Icon: Slate 700
  - Hover: Subtle shadow

## Spacing System

| Level | Value |
|-------|-------|
| XS | 4px |
| SM | 8px |
| MD | 12px |
| LG | 16px |
| XL | 20px |
| 2XL | 24px |
| 3XL | 32px |

## Shadows

### Subtle Shadow
```
BoxShadow(
  color: Colors.black.withOpacity(0.05),
  blurRadius: 4,
)
```

### Small Shadow
```
BoxShadow(
  color: Colors.black.withOpacity(0.1),
  blurRadius: 8,
  offset: Offset(0, 2),
)
```

### Large Shadow
```
BoxShadow(
  color: AppTheme.maroon.withOpacity(0.3),
  blurRadius: 20,
  offset: Offset(0, 8),
)
```

## Border Radius

| Size | Value |
|------|-------|
| Small | 8px |
| Medium | 10px |
| Large | 12px |
| Extra Large | 16px |
| Circle | 50% |

## Animations

### Duration Standards
- Quick: 150ms (for state changes)
- Standard: 200ms (for transitions)
- Slow: 300ms (for page transitions)

### Common Animation Types
- **Fade**: Opacity from 0 to 1
- **Slide**: Transform Y or X
- **Scale**: Transform scale
- **Color**: Gradient or color transitions

## Implementation References

### Color Usage in Code
```dart
// Primary brand
const Color maroon = Color(0xFF8B1C3E);

// Gradients
gradient: const LinearGradient(
  colors: [AppTheme.maroon, AppTheme.maroonDark],
)

// Status badges
StatusBadge.fromStatus('Active') // Green
StatusBadge.fromStatus('Pending') // Amber
StatusBadge.fromStatus('Rejected') // Red
```

### Button Implementation
```dart
// Primary button
ElevatedButton(
  onPressed: () {},
  child: const Text('Sign In'),
)

// Secondary button
OutlinedButton(
  onPressed: () {},
  child: const Text('Cancel'),
)
```

### Card Implementation
```dart
Card(
  child: Container(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        // Content
      ],
    ),
  ),
)
```

## Responsive Design

### Breakpoints
- **Mobile**: < 500px - Single column
- **Tablet**: 500px - 900px - Two columns
- **Desktop**: > 900px - Three+ columns

### Layout Adjustments
- Drawer on mobile, sidebar on desktop
- Adaptive grid for stats and cards
- Touch-friendly tap targets (48x48px minimum)

## Accessibility

### Color Contrast
- Text: Minimum 4.5:1 ratio
- Large Text (18px+): Minimum 3:1 ratio
- UI Components: Minimum 3:1 ratio

### Touch Targets
- Minimum size: 48x48px
- Ideal size: 56x56px
- Padding between targets: 8px minimum

### Icons
- Minimum size: 18x18px
- Primary size: 20x20px
- Large size: 24x24px

## Migration Notes from siasprototype

This Flutter implementation mirrors the React siasprototype with the following adaptations:

1. **Animations**: Flutter's AnimatedSwitcher replaces framer-motion
2. **Icons**: Material Icons replace lucide-react
3. **Styling**: Flutter theme replaces Tailwind CSS
4. **Layout**: Drawer replaces sidebar on mobile
5. **Forms**: Flutter TextFields replace HTML inputs

## Best Practices

1. **Always use AppTheme constants** instead of hardcoding colors
2. **Use the spacing system** for consistent margins and padding
3. **Apply shadows for depth** - don't rely on borders alone
4. **Maintain typography hierarchy** - match the text styles guide
5. **Use animations for feedback** - state changes should feel responsive
6. **Test on multiple screen sizes** - responsive design is essential
7. **Ensure contrast ratios** - accessibility matters
8. **Keep button sizing consistent** - match the style guide

## File Locations

- **Theme**: `lib/theme/app_theme.dart`
- **Widgets**: `lib/widgets/shared_widgets.dart`
- **Screens**: `lib/screens/`
- **Models**: `lib/models/`

## Support

For design questions or updates, refer to:
1. This design system document
2. The siasprototype React implementation
3. The app_theme.dart file for color definitions
