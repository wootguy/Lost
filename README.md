# Lost
Ever get lost or disoriented in the game? This plugin creates a craptastic HUD for tracking other players in the server. It's not perfect and gets clipped into corners and walls a lot, but if I don't release this now it will rot on my drive forever.

Only ASCII names work correctly. Names longer than 16 characters will be shortened.

Here's a demo of it:

[![Demo Video](https://img.youtube.com/vi/fUjm_fr7VWs/0.jpg)](https://www.youtube.com/watch?v=fUjm_fr7VWs)

# Commands

`.lost` = Toggles tracking for all players  
`.lost \` = Toggles name tags for all players (does not show through walls).

If you specify a player name after the `.lost` command, tracking will be enabled for only that player (e.g. `.lost w00tguy`). You can use a partial name or steamID here too (e.g. `.lost guy`). Names with spaces in them should be surrounded with quotes.

# Server Impact

Due to limitations with temporary entities, each font character is an individual sprite. 96 sprites are precached in total. The download size is only 107 KB so this goes pretty quickly even on slow DL (about 13 seconds).

The effect is created with temporary entities, so there should be no stability problems. Net usage might be high with a lot of players though. The doomsday scenario of 32 players all >100 meters away would create about 640 sprites, which is a bit over the max allowed before things start disappearing (~500). Clients can disable the tracking to fix the lag when this happens. You can also change the max name length in the script (line 16) if you have 26+ slots.
