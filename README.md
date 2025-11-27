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
  * GREEN - Caution threshold (TTK ≤60 seconds)
  * WHITE - Normal state
- Sample throttling (1 second interval) for better accuracy
- Display smoothing to reduce jumpiness
- Test mode to track any enemy in combat
- Per-target tracking with automatic cleanup

USAGE:
Shift-drag when unlocked to move - clickthrough enabled when locked

COMMANDS:

**Basic Commands:**
- `/ttk` - Show help

**UI Configuration:**
- `/ttk lock` - Lock frame (enables click-through)
- `/ttk unlock` - Unlock frame (allows dragging with Shift)
- `/ttk name on|off` - Show/hide label text
- `/ttk combathide on|off` - Auto-hide frame when out of combat
- `/ttk execute on|off` - Show/hide execute phase timer
- `/ttk dps on|off` - Show/hide DPS display
- `/ttk hp on|off` - Show/hide HP display

**Calculation Settings:**
- `/ttk conservative <0.9-1.0>` - Set conservative factor (default: 0.95)
  - Lower values = more cautious time estimates
- `/ttk minsample <seconds>` - Set minimum sample time (default: 2.0)
  - Range: 0.5-10.0 seconds before showing estimates
- `/ttk smooth <0.1-0.3>` - Set display smoothing factor (default: 0.15)
  - Lower values = smoother display, higher = more responsive

**Development & Debug:**
- `/ttk test` - Toggle test mode (track any enemy vs normal tracking)
- `/ttk status` - Show addon status, settings, and tracked targets
- `/ttk debug` - Show detailed RLS debug info for current target

TROUBLESHOOTING:

**Settings not persisting after /reload:**

If your settings reset every time you reload the UI, you have corrupted SavedVariables from an older version of the addon.

To fix this:
1. Exit WoW completely
2. Delete the old SavedVariables file:
   - Path: `WTF/Account/YOURACCOUNTNAME/SavedVariables/TimeToKill.lua`
3. Launch WoW - you should see "First run - initializing settings" in green
4. Configure your settings (`/ttk hp off`, move frame position, etc.)
5. `/reload` to test - settings should now persist!

**Note:** Once properly initialized, both `/reload` and clean exit will save your settings. The issue is only caused by corrupted old SavedVariables that need to be deleted.
