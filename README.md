# Lost
Ever get lost or disoriented in the game? This plugin creates a craptastic HUD for tracking other players in the server. It's not perfect and gets clipped into corners and walls a lot, but if I don't release this now it will rot on my drive forever.

Only ASCII names work correctly. Names longer than 16 characters will be shortened.

Here's a demo of it:

[![Demo Video](https://img.youtube.com/vi/fUjm_fr7VWs/0.jpg)](https://www.youtube.com/watch?v=fUjm_fr7VWs)

# Commands

- `.lost` = Toggles tracking for all players  
- `.lost delay [1-10]` = Change how often tags are updated. Increase this if you're getting excessive flickering.
- `.lost mode [mode]` = Change tracking mode
  - `.lost mode full` = Default. Show name tags for visible/invisible players
  - `.lost mode simple` = Only show dots for invisible players.
  - `.lost mode local` = Show name tags for visible players, and nothing for invisible players.

If you specify a player name after the `.lost` command, tracking will be enabled for only that player (e.g. `.lost w00tguy`). You can use a partial name or steamID here too (e.g. `.lost guy`). Names with spaces in them should be surrounded with quotes. You can repeat this command to track other players.

# CVars

`as_command lost.disabled 1` = disables the plugin

# Server Impact

The effect is created with temporary entities, so there should be no stability problems. Net usage might be high with a lot of players though. The worst case scenario of 32 players all >1000 meters away with long names would create 63 beams and 29 sprites. Clients can disable the tracking or increase the update delay with `.lost delay` if there is any lag or flickering.

Only 1 sprite is precached.
