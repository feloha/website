# Roblox black-hole merge game — UI work handoff (2026-10-01)

## How scripts are delivered
- All scripts live in `feloha/website`, branch `claude/cloud-session-definition-2ehdjd`, folder `roblox-scripts/` (one `.lua` per script).
- Installed with a Studio **Command Bar** snippet (needs Game Settings → Security → Allow HTTP Requests). Pin the URL to a commit SHA so caching can't serve old files:

```lua
local H=game:GetService("HttpService") local B="https://raw.githubusercontent.com/feloha/website/<COMMIT_SHA>/roblox-scripts/"
local RS,SP=game:GetService("ReplicatedStorage"),game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
for _,f in ipairs({{"StudSurface",RS,"ModuleScript"},{"MainHUD",SP,"LocalScript"}}) do
 local s=f[2]:FindFirstChild(f[1]) or Instance.new(f[3]) s.Name=f[1] s.Source=H:GetAsync(B..f[1]..".lua",true) s.Parent=f[2]
 print("updated",f[1],#s.Source,"chars") end
```
- ModuleScripts go in ReplicatedStorage; LocalScripts in StarterPlayer > StarterPlayerScripts. Backups in ServerStorage are inert.
- Scripts print build stamps on Play (e.g. `[MainHUD] build 2026-10-01h`, `[StudSurface] build 2026-10-01h`) to confirm the running copy.
- Luau main chunks have a 200-local limit (MainHUD, TutorialClient are near it): group values in tables / do-blocks.

## User preferences / constraints
- Openable scripts, not downloads; full scripts; cost-conscious.
- Desktop unchanged unless asked; keep existing art/asset ids; don't touch combo/currency/DataStore logic.
- Cartoon, Pet-Sim-style UI. All game UI is built by scripts (nothing in StarterGui).
- Responsive work goes through the shared systems, not one-off `if mobile then Position = ...` patches.

## Shared systems (ReplicatedStorage)
- **UiResponsive**: Screen, ToScreen, SafeRect, SafeRectIn(gui), TopInset, Layout ("compact" short side < 520 / "medium" / "wide"), Boost, ModalArea, UseModalInsets, FitScale/FitPanel, Space {XS4,S8,M12,L18,XL28}, TouchScroll, InputMode, Changed.
- **GuiManager**: Register/Open/Close/Toggle/GetCurrent/GetFrame/GetState (CLOSED/OPENING/OPEN/CLOSING), Changed signal. Windows get `PopupInputSink` (under content) and `PopupTransitionShield` (while animating) so taps never fall through to the HUD. Option `InputFrame` for full-screen groups (Playtime, Inventory).
- **UIInputRouter** (new): `Router.Signal(button, action, opts):Connect(fn)` / `Router.Bind`. One action per tap gesture, no acting on HUD buttons from a press that began inside an open window, 0.25 s window-transition lock, duplicate-registration warning, Studio `[UI INPUT]` log. All HUD window buttons, tutorial buttons, Attack/Drop, offer card are routed.
- **UILayoutManager** (new): registry with priorities, rect collisions with 12–24 px padding, candidate spots with least displacement + hysteresis, 0.2 s moves, FULL/COMPACT variants, UI states MODAL > TUTORIAL > INTERACTION > COMBAT > EVENT > NORMAL, occupancy budget (30%), gameplay clear zone, reserved joystick/jump zones, CollectionService tag `UILayout`, Studio Ctrl+J visualiser + "UI COLLISION" warnings. Registered: TutorialDialog (P100), MainHUD zones (P75–80), CarryCard (P70, movable, compact in tutorial), ComboMeter (P55), HudStack EventColumn (P40, condenses).
- **HudStack**: top-centre event/announcement column; `SetDensity("FULL"|"COMPACT")`.
- **StudSurface** (current build 1h): drawn molded studs. `Apply(face, {Color, Icon, Label, KeepOut={frames}, CornerRadius, RimInset, Behind="fade"|"hide", Mirror, Marks={{gapCol,gapRow,size}}, SizeShare, PitchShare, MaxColumns, MaxRows, MinFace, ...})`. Each stud = shadow + darker wall + lit dome + white glint. Symmetric grid, corner studs dropped inside rounded rim, "+" marks placed in grid gaps, relayout only when design size/name changes (no hover blinking). The supplied texture rbxassetid://140302758156355 is NOT used (it rendered as ridges); `StudSurface.StudImage` can switch to a single-stud image.

## Main client scripts (StarterPlayerScripts)
- **MainHUD**: top actions (Upgrade / Lock Base PNG art), left menu (Store, Leaderboards, Index, Rebirth, Inventory), Stardust + Gems (Gems left edge = Stardust left edge, `GEMS_SHIFT = 0`), Playtime slot, Upgrade window.
  - Left menu: `buildCohesiveNav(text, color, iconId, spec)` molded tiles, `NAV_SLOT = 208x86`, gap 15, `NAV` table (radius 28, lip 7, rim 4.8, inner rim, icon 74x58, label 31 px with 4 px outline, gloss streak + dot, `NAV.Marks`, `NAV.Stud` = 9x4 grid, Behind "hide"). `fitNavStack()` keeps menu + currency cluster between top bar and bottom edge (slides up, shrinks to ≥ 72%). Phones: 2x3 icon-only grid.
  - Playtime Awards: the finished artwork `UIAssets.PlaytimeButton` = rbxassetid://124105198585397 (user confirmed correct), slot 274x206 (`PLAYTIME_HEIGHT`, ratio 1.33), studs on its plate via `PLAYTIME_ZONES` (Plate/Gift/Text lines/Sparkles as picture shares), Mirror off; fallback plate until loaded; button name stays "Playtime Awards" (PlaytimeAwardsClient finds it by name).
  - Upgrade: phones +10% uniform scale (may use free middle of top-bar strip), larger price text.
- **StoreClient**: phones/tablets use sideways card rows (~3.15 cards phone, ~4.15 tablet), compact phone header, text minimums scale on phones.
- **BlackHoleCarryClient**: Attack/Drop card FULL/COMPACT; phones always compact and sized from usable height; padded invisible touch areas; registered with layout manager.
- **TutorialClient**: Nibbles dialog; on phones rises under the top HUD when the carry card shows; thinner spotlight ring on phones. The small Nibbles replay button by Gems was removed (no hitbox).
- **SettingsClient**: gear in molded style (rim, lip, studs; none at 40 px phone size).
- **HudLayoutAudit** (Studio only): Ctrl+L zone audit, Ctrl+H hitbox visualiser with "HITBOX OVERLAP" warnings, `[TapTrace]` tap logging.
- Others touched earlier: PlaytimeAwardsClient (phone layout, featured jackpot), StardustDropClient (combo meter), MutationClient, MergeGuideClient, LimitedOfferClient, WelcomeBackClient, Index/Inventory/Leaderboards/RebirthClient, AssetCheckClient.

## Open items / next steps
- Visual check in Studio of the latest stud domes on the menu and the Playtime artwork; tune `NAV.Stud`, `PLAYTIME_ZONES`, stud shading in `StudSurface.buildStud`.
- The user's references: chunky molded toy-brick buttons (thick navy rim, dark lower lip, bright inner rim, glossy upper-left streak, colour-matched glossy studs, "+" marks, big icons, big white outlined labels).
- Wrong-window-opens bug: fixed structurally (GuiManager shield/sink + UIInputRouter); confirm with `[UI INPUT]` logs if it recurs.
- Nothing here has been run in Studio by the assistant; all verification has been compile checks + numeric layout simulation.
