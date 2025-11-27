TimeToKill - Advanced time-to-kill estimation using RLS (Recursive Least Squares) algorithm

CREDITS:
- Original EliteWarriorCombat by jlabranche
- Improved timer updates by MarcelineVQ and Ehawne (RLS algorithm implementation)
- SuperWoW support and integration by Torio/jrc13245

FEATURES:
- Accurate TTK estimation with dual RLS estimators
- DPS display (formatted with K/M suffixes)
- Time-to-Execute (TTE) - shows time until target reaches 20% HP
- HP display with formatted numbers (1.5M, 45K, etc.)
- Color-coded warnings:
  * RED - Target in execute range (≤20% HP)
  * YELLOW - Warning threshold (TTK ≤40 seconds)
  * WHITE - Normal state
- Sample throttling (1 second interval) for better accuracy
- Display smoothing to reduce jumpiness
- Test mode to track any enemy in combat
- Per-target tracking with automatic cleanup

USAGE:
Shift-drag when unlocked to move - clickthrough enabled when locked

COMMANDS:
 /ttk - Show help
 /ttk lock|unlock - Toggle frame lock
 /ttk name on|off - Show/hide label text
 /ttk combathide on|off - Hide frame when out of combat
 /ttk conservative <0.9-1.0> - Set conservative factor (default 0.95)
 /ttk minsample <seconds> - Set minimum sample time (default 2.0)
 /ttk smooth <0.1-0.3> - Set display smoothing (default 0.15, lower = smoother)
 /ttk test - Toggle test mode (track any enemy vs normal tracking)
 /ttk status - Show addon status and RLS settings
 /ttk debug - Show detailed RLS debug info for current target
