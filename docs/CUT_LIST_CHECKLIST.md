# Simplification cut and verification checklist

Core: steal a boss coffin → place it in the pen → murder rounds advance its clock → hatch a knife
that earns cash → upgrade Speed and room → steal deeper. Vault servers retain their direct-knife
variant. Fixed Murderer perks, the tutorial showcase and the Speed prize tuning stay as agreed.

- [x] Studio pen prototype removed (`6828728`).
- [x] Trading/team-up and Players menu removed; friend bonus and Invite stay (`dea4efb`).
- [x] Server goals/events removed (`b7a1eb5`).
- [x] Innocent powers, energy, UI, shopkeeper and hooks removed (`aa28cfc`).
- [x] Knife power rolls, XP/levels, rerolls and Sheriff power theft removed (`18e510d`).
- [x] Case shops/reels/odds, Lucky Blocks, merchant and free chest removed; rewards use CoffinService (`59709fc`).
- [x] Finish raid removal: no raid initialization, remotes, prompts, gate health, summons or wall purchases.
- [x] Keep carrier knockdowns while preserving sealed contents through drop, pickup and round suspension.
- [x] Close full-pen/paid-reward routes that bypass the coffin clock.
- [x] Remove health progression, Titan/health products (refunded once). The hurt-only health bar stays as feedback.
- [x] Remove Heat state effects, income multiplier, offers and displays; Murderer chance meter kept (ChanceMeter).
- [x] Remove luck potions/server luck and their store/UI/runtime hooks; rebirth + Luck pass mutation/size luck kept.
- [ ] Retired paid products/pass ownership receive compatible, once-only replacement value.
- [ ] Audit receipt retries, save failure and duplicate requests.
- [ ] Final HUD/menu/config/source sweep; update obsolete architecture documentation.
- [ ] Lint, formatting, types, regression tests, clean Studio boots and both coffin/vault variants.

Historical save fields and retired purchase IDs may remain for compatibility. They must not expose
or reactivate removed systems. Decorative asset names (for example a trophy case or Fire.Heat)
are unrelated to gameplay containers and player Heat.
