enum tracking_modes {
	MODE_FULL,	 // player name tags shown through walls and shown locally
	MODE_INVIS,  // player name tags shown through walls only, not locally
	MODE_LOCAL,  // player name tags shown on visible players only. No dots.
	MODE_SIMPLE  // player dots shown through walls
}

class PlayerState
{
	dictionary targetPlrs; // player state keys
	CScheduledFunction@ interval; // handle to the interval
	bool enabled = false;
	bool filteredTracking = false;
	int updateRate = 1;
	int mode = MODE_FULL;
	bool hidden = false;
	float pingTime = 0; // player is pinging if >0
	float lastPingTime = 0;
}
 

// persistent-ish player data, organized by steam-id or username if on a LAN server, values are @PlayerState
dictionary player_states;
bool abort_updates = false;

string font_sprite = "sprites/as_lost/consolas96.spr";
string dot_sprite = "sprites/as_lost/dot.spr";
int pingSpriteIdx = -1;
int dotSpriteIdx = -1;
string sonar_sound = "as_lost/sonar.wav";
int maxNameLength = 12;

CCVar@ cvar_disabled;

// Will create a new state if the requested one does not exit
PlayerState@ getPlayerState(CBasePlayer@ plr)
{
	if (plr is null or !plr.IsConnected())
		return null;
		
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN' or steamId == 'BOT') {
		steamId = plr.pev.netname;
	}
	
	if ( !player_states.exists(steamId) )
	{
		PlayerState state;
		player_states[steamId] = state;
		//println("ADDED STATE FOR: " + steamId);
	}
	return cast<PlayerState@>( player_states[steamId] );
}

void init()
{
	populatePlayerStates();
	//g_Scheduler.SetTimeout("loadMapWaypoints", 0.5);
	//g_Scheduler.SetInterval("renderAllWaypoints", 0.1);
}

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "w00tguy123 - forums.svencoop.com" );
	
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );
	g_Hooks.RegisterHook( Hooks::Player::ClientDisconnect, @ClientLeave );
	g_Hooks.RegisterHook( Hooks::Player::ClientPutInServer, @ClientJoin );
	
	g_Hooks.RegisterHook( Hooks::Game::MapChange, @MapChange );
	
	@cvar_disabled = CCVar("disabled", 0, "disables tracking", ConCommandFlag::AdminOnly);
	
	init();
}

void MapInit()
{
	g_Game.PrecacheModel(font_sprite);
	g_Game.PrecacheModel(dot_sprite);
	pingSpriteIdx = g_Game.PrecacheModel("sprites/laserbeam.spr");
	dotSpriteIdx = g_Game.PrecacheModel("sprites/glow01.spr");
	
	g_Game.PrecacheGeneric("sound/" + sonar_sound);
	g_SoundSystem.PrecacheSound(sonar_sound);
	
	abort_updates = false;
}

HookReturnCode MapChange()
{
	abort_updates = true;
	
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );

		if (state.interval !is null)
			g_Scheduler.RemoveTimer(state.interval);
	}
	
	player_states.deleteAll();
	return HOOK_CONTINUE;
}

void populatePlayerStates()
{	
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "player"); 
		if (ent !is null)
		{
			CBasePlayer@ plr = cast<CBasePlayer@>(ent);
			getPlayerState(plr);
			//println("TRY STATE FOR: " + plr.pev.netname);
		}
	} while (ent !is null);
}

HookReturnCode ClientJoin( CBasePlayer@ plr )
{
	getPlayerState(plr);
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientLeave(CBasePlayer@ leaver)
{
	string steamId = g_EngineFuncs.GetPlayerAuthId( leaver.edict() );
	if (steamId == 'STEAM_ID_LAN') {
		steamId = leaver.pev.netname;
	}
		
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		if (stateKeys[i] == steamId)
		{
			if (state.interval !is null)
				g_Scheduler.RemoveTimer(state.interval);
			break;
		}
	}
	player_states.delete(steamId);
	
	return HOOK_CONTINUE;
}

void displayText(Vector pos, CBasePlayer@ observer, CBaseEntity@ plr, string text, Color color, float scale, int life, bool dot_only)
{
	if (dot_only) {
		text = "O";
	}
	array<string> lines = text.Split("\n");
	
	// adjust scale so that it is readable at a distance
	float dist = (pos - (observer.pev.origin + observer.pev.view_ofs)).Length();
	scale = Math.min(25.0f, (dist / 1024.0f) + scale);
	
	Math.MakeVectors( observer.pev.v_angle );
	Vector lookDir = g_Engine.v_forward;
	
	// flattened look direction
	Vector flatLookDir = lookDir;
	flatLookDir.z = 0;
	flatLookDir = flatLookDir.Normalize();
	
	// text axis
	Vector textAxis = CrossProduct(flatLookDir, Vector(0,0,1));
	//te_beampoints(observer.pev.origin, observer.pev.origin + textAxis*128);
	
	Vector newlineAxis = CrossProduct(lookDir, textAxis).Normalize();
	//te_beampoints(observer.pev.origin, observer.pev.origin + newlineAxis*128);
	
	float charWidth = 12.0f*scale;	
	float charHeight = 18.0f*scale;
	pos.z += charHeight*lines.length()*0.5f;
	
	if (dot_only) {
		charWidth = charHeight = 32.0f;
		scale *= 1.5f;
	}
	
	// calculate a bounding square for the text
	float height = lines.length()*charHeight;
	float width = 0;
	for (uint k = 0; k < lines.length(); k++)
		if (int(lines[k].Length()) > width)
			width = lines[k].Length();
	width *= charWidth;
	
	Vector textOri = pos + newlineAxis*(height*0.5f - charHeight*0.5f);
	Vector textVert = newlineAxis*height*0.5f;
	Vector textHori = textAxis*width*0.5f;
	

	TraceResult tr, tr2;
	CBaseEntity@ pHit, pHit2;
	edict_t@ no_collide = plr !is null ? plr.edict() : null;
	
	//te_beampoints(textOri - textVert, textOri + textVert);
	
	
	// make sure text isn't vertically colliding with anything
	g_Utility.TraceHull( textOri - textVert, textOri + textVert, ignore_monsters, point_hull, no_collide, tr );
	g_Utility.TraceHull( textOri + textVert, textOri - textVert, ignore_monsters, point_hull, no_collide, tr2 );
	if (tr.flFraction < 1.0f or tr2.flFraction < 1.0f)
	{
		float topDist = tr.flFraction;
		float bottomDist = tr2.flFraction;
		
		// move the least amount necessary, and in the direction that the player will see it best
		bool belowPlayer = textOri.z < observer.pev.origin.z + observer.pev.view_ofs.z;
		//println("BELOW? " + belowPlayer);
		if ((topDist > bottomDist or bottomDist == 1) and topDist < 1 and (belowPlayer or bottomDist == 1))
			pos = pos - newlineAxis*height*(1.0f-topDist);
		else
			pos = pos + newlineAxis*height*(1.0f-bottomDist);
		textOri = pos + newlineAxis*(height*0.5f - charHeight*0.5f);
	}
	
	// make sure text isn't horizontally colliding with anything
	g_Utility.TraceHull( textOri - textHori, textOri + textHori, ignore_monsters, point_hull, no_collide, tr );
	g_Utility.TraceHull( textOri + textHori, textOri - textHori, ignore_monsters, point_hull, no_collide, tr2 );
	if (tr.flFraction < 1.0f or tr2.flFraction < 1.0f)
	{
		float topDist = tr.flFraction;
		float bottomDist = tr2.flFraction;
		
		// move the least amount necessary
		if ((topDist > bottomDist or bottomDist == 1) and topDist < 1)
			pos = pos - textAxis*width*(1.0f-topDist);
		else
			pos = pos + textAxis*width*(1.0f-bottomDist);
		textOri = pos + newlineAxis*(height*0.5f - charHeight*0.5f);
	}
	
	//te_beampoints(observer.pev.origin, textOri + textVert);
	
	if (dot_only) {
		te_sprite(pos, dot_sprite, int(scale*10), color.a, MSG_ONE_UNRELIABLE, observer.edict());
		return;
	}
	
	Vector beamCharExtent = newlineAxis*charHeight*0.5f;
	int beamWidth = int(charWidth*4);
	float y = 0;
	for (uint k = 0; k < lines.length(); k++)
	{
		float x = -float(lines[k].Length() * charWidth) / 2.0f;
		x += charWidth * 0.5f;

		for (uint i = 0; i < lines[k].Length(); i++)
		{
			int c = int(lines[k][i]) - 32;			
			if (c == 0) {
				continue; // don't render spaces
			} else if (c < 0 || c > 94) {
				c = 0; // show unknown char
			}
			
			Vector charPos = pos + textAxis*x + newlineAxis*y;

			te_beampoints(charPos - beamCharExtent, charPos + beamCharExtent, font_sprite, c, 0, life, beamWidth, 0, color, 0, MSG_ONE_UNRELIABLE, observer.edict());
			
			x += charWidth;
		}

		y += charHeight;
	}
}

// display name overhead
Vector showNameTag(CBasePlayer@ observer, LostTarget targetInfo, PlayerState@ state, bool dot_only)
{
	CBaseEntity@ target = targetInfo.h_target;
	
	if (observer is null or target is null or abort_updates)
		return Vector();
	
	Vector tagPos = targetInfo.lastTagOrigin;
	bool useTagPos = tagPos.x != 0 or tagPos.y != 0 or tagPos.z != 0;
	
	string name = target.pev.netname;
	
	if (int(name.Length()) > maxNameLength)
	{
		int middle = name.Length() / 2;
		name = name.SubString(0, 5) + ".." + name.SubString(name.Length()-5, name.Length());
	}
	
	TraceResult tr, tr2;
	Vector observerHead = observer.pev.origin + observer.pev.view_ofs;
	Vector targetHead = target.pev.origin + target.pev.view_ofs + Vector(0,0,40);
	Vector delta = targetHead - observerHead;
	float dist = delta.Length();
	g_Utility.TraceHull( observerHead, targetHead, ignore_monsters, point_hull, observer.edict(), tr );
	g_Utility.TraceHull( observerHead, target.pev.origin, ignore_monsters, point_hull, observer.edict(), tr2 );
	float maxDist = Math.min(2048.0f, tr.flFraction*dist);
	
	CBaseEntity@ pHit = g_EntityFuncs.Instance( tr.pHit );
	CBaseEntity@ pHit2 = g_EntityFuncs.Instance( tr2.pHit );
	bool lineOfSight = pHit !is null and pHit.entindex() == target.entindex() or tr.flFraction == 1;
	bool bodySight = pHit2 !is null and pHit2.entindex() == target.entindex() or tr2.flFraction == 1;
	bool isSelf = observer.entindex() == target.entindex();
	lineOfSight = lineOfSight or isSelf;
	
	if (isSelf)
		return Vector();
	
	float meters = Math.max(0, (dist/33.0f) - 1.0f);
	string dstr = "" + int(meters) + "m\n";
	
	Vector pos;
	if (lineOfSight)
	{
		if (!dot_only && state.mode != MODE_INVIS) {
			pos = target.pev.origin;
			pos.z += 50.0f;
			dstr = "";
			
			if (useTagPos) {
				pos = tagPos;
			}
			
			displayText(pos, observer, target, dstr + name, targetInfo.color, 0.1f, state.updateRate, false);
			return pos;
		}
	}
	else if (state.mode != MODE_LOCAL)
	{		
		if (useTagPos) {
			pos = tagPos;
		}
		else if (bodySight) {
			dstr = "";
			pos = target.pev.origin - delta.Normalize()*32;
		} 
		else {
			// player is completely obscured
			// retrace to origin which is more accurate to where the player is, rather than the tag
			pos = tr2.vecEndPos + tr2.vecPlaneNormal*4;
		}
		
		displayText(pos, observer, target, dstr + name, targetInfo.color, 0.1f, state.updateRate, dot_only);
		return pos;
	}
	
	return Vector();
}

class LostTarget {
	EHandle h_target;
	float observerDot; // how closely the target aligns with the observer's center of view
	Vector lastTagOrigin; // position of the nametag at the time of the ping
	Color color;
}

const float PING_DURATION = 2.5f;

void helpLostPlayer(EHandle h_plr, array<LostTarget> targets)
{
	CBasePlayer@ plr = cast<CBasePlayer@>(h_plr.GetEntity());
	
	if (plr is null) {
		return;
	}
	
	PlayerState@ observerState = getPlayerState(plr);
	bool isPinging = observerState.pingTime > 0;
	float pingAge = g_Engine.time - observerState.pingTime;
	if (isPinging and pingAge > PING_DURATION) {
		observerState.enabled = false;
		observerState.pingTime = 0;
		return;
	}
	
	Math.MakeVectors( plr.pev.v_angle );
	Vector lookDir = g_Engine.v_forward;
	lookDir.Normalize();
	bool saveTagPositions = targets.size() == 0;

	if (targets.size() == 0) {
		for (int i = 1; i <= g_Engine.maxClients; i++) {
			CBasePlayer@ target = g_PlayerFuncs.FindPlayerByIndex(i);
			
			if (target is null or !target.IsConnected()) {
				continue;
			}
			
			PlayerState@ state = getPlayerState(target);
			string steamId = getPlayerUniqueId(target);
			
			if (target is null or !target.IsConnected() or target.entindex() == plr.entindex())
				continue;
			if (!target.IsAlive() and target.GetObserver().IsObserver())
				continue;
			if (target.Classify() != plr.Classify())
				continue;
			if (observerState.filteredTracking and !observerState.targetPlrs.exists(steamId))
				continue;
			if (state.hidden) {
				if (observerState.filteredTracking) {
					observerState.targetPlrs.delete(steamId);
					g_PlayerFuncs.SayText(plr, "" + target.pev.netname + " is now hiding and can't be tracked.\n");
				}
				continue;
			}
			
			Vector delta = (target.pev.origin - plr.pev.origin).Normalize();
			
			LostTarget lostTarget;
			lostTarget.h_target = EHandle(target);
			lostTarget.observerDot = DotProduct(lookDir, delta);
			lostTarget.color = WHITE;
			
			targets.insertLast(lostTarget);
		}
	} else {
		// pinging
		
		for (uint i = 0; i < targets.size(); i++) {
			CBasePlayer@ target = cast<CBasePlayer@>(targets[i].h_target.GetEntity());
			if (target is null or !target.IsConnected()) {
				continue;
			}
			
			Vector delta = (target.pev.origin - plr.pev.origin).Normalize();
			targets[i].observerDot = DotProduct(lookDir, delta);
			
			float pingLeft = PING_DURATION - pingAge;
			float brightness = pingLeft > 1.0f ? 1.0f : pingLeft;
			brightness = brightness*brightness; // fade out curve
			targets[i].color = Color(255, 255, 255, brightness * 255);
		}
	}
	
	if (observerState.mode != MODE_SIMPLE) {
		if (targets.size() > 0) {
			targets.sort(function(a, b) {		
				return a.observerDot > b.observerDot; 
			});
		}
	}
	
	for (uint i = 0; i < targets.size(); i++) {
		CBasePlayer@ target = cast<CBasePlayer@>(targets[i].h_target.GetEntity());
		if (target is null or !target.IsConnected()) {
			continue;
		}
	
		Vector tagPos;
		if (i < 3 && observerState.mode != MODE_SIMPLE) {
			tagPos = showNameTag(plr, targets[i], observerState, false);
		} else if (observerState.mode != MODE_LOCAL) {
			tagPos = showNameTag(plr, targets[i], observerState, true);
		}
		
		if (saveTagPositions) {
			targets[i].lastTagOrigin = tagPos;
		}
	}
	
	if (observerState.enabled && cvar_disabled.GetInt() == 0) {
		float rate = Math.max(observerState.updateRate / 10.0f, 0.1f);
		g_Scheduler.SetTimeout("helpLostPlayer", rate, h_plr, isPinging ? targets : array<LostTarget>());
	}
}

string getPlayerUniqueId(CBasePlayer@ plr)
{
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN' or steamId == 'STEAM_ID_BOT' or steamId == 'BOT') {
		steamId = plr.pev.netname;
	}
	return steamId;
}

// get player by name, partial name, or steamId
CBasePlayer@ getPlayer(CBasePlayer@ caller, string name)
{
	name = name.ToLowercase();
	int partialMatches = 0;
	CBasePlayer@ partialMatch;
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "player");
		if (ent !is null) {
			CBasePlayer@ plr = cast<CBasePlayer@>(ent);
			string plrName = string(plr.pev.netname).ToLowercase();
			string plrId = getPlayerUniqueId(plr).ToLowercase();
			if (plrName == name)
				return plr;
			else if (plrId == name)
				return plr;
			else if (plrName.Find(name) != uint(-1))
			{
				@partialMatch = plr;
				partialMatches++;
			}
		}
	} while (ent !is null);
	
	if (partialMatches == 1) {
		return partialMatch;
	} else if (partialMatches > 1) {
		g_PlayerFuncs.SayText(caller, 'There are ' + partialMatches + ' players that have "' + name + '" in their name. Be more specific.');
	} else {
		g_PlayerFuncs.SayText(caller, 'There is no player named "' + name + '"');
	}
	
	return null;
}

bool doCommand(CBasePlayer@ plr, const CCommand@ args)
{
	PlayerState@ state = getPlayerState(plr);
	
	if ( args.ArgC() >= 1 )
	{
		if (args[0] == ".ping" || args[0] == ".lost") {
			float delta = g_Engine.time - state.lastPingTime;
			float waitTime = (PING_DURATION + 0.1f) - delta;
			if (waitTime > 0) {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCENTER, "Wait " + int(waitTime + 0.99f) + " seconds\n");
				return true;
			}
		}
		
		if (args[0] == ".ping") {
			if (state.enabled) {
				g_PlayerFuncs.SayText(plr, "Player tracking disabled\n");
			}
			state.enabled = true;
			state.pingTime = g_Engine.time + 0.3f;
			state.lastPingTime = state.pingTime;
			g_Scheduler.SetTimeout("helpLostPlayer", 0.3f, EHandle(plr), array<LostTarget>());
			
			int life = 8;
			int width = 8;
			Color color = Color(0, 255, 0, 16);
			te_beamtorus(plr.pev.origin, 3000.0f, pingSpriteIdx, 0, 16, life, width, 0, color, 0,
						 MSG_ONE_UNRELIABLE, plr.edict());
						 
			g_SoundSystem.PlaySound(plr.edict(), CHAN_VOICE, sonar_sound, 0.5f, ATTN_NONE, 0, 100, plr.entindex());
			
			return true;
		}
		if ( args[0] == ".lost" )
		{
			if (cvar_disabled.GetInt() != 0) {
				g_PlayerFuncs.SayText(plr, "Player tracking is disabled on this map.\n");
				return true;
			}
			CBasePlayer@ targetPlr = null;
			if ( args.ArgC() >= 3 && args[1] == "delay" ) {
				int newRate = atoi(args[2]);
				
				newRate = Math.min(10, newRate);
				newRate = Math.max(1, newRate);
				
				g_PlayerFuncs.SayText(plr, "Update delay set to " + newRate + "\n");
				
				state.updateRate = newRate;
				return true;
			}
			
			if (args.ArgC() >= 2 && args[1] == "help") {
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\n--------------------------------Lost Commands--------------------------------\n\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'This plugin helps you find other players.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, 'Observers and players on enemy teams are not tracked.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nType ".ping" to quickly check for other players.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nType ".lost" to toggle player tracking.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nType ".lost [player name]" to toggle tracking for a specific player.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    - Steam IDs and partial names also work (e.g. "guy" instead of "w00tguy")\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    - Names with spaces in them should be surrounded with quotes\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    - Repeat this command to track/untrack more players\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nType ".lost hide [1/0]" to prevent or allow others to track you.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nType ".lost delay [1-10]" to change how often tags are updated.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    - Increase this if you\'re getting excessive flickering\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\nType ".lost mode [mode]" to change tracking mode.\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    - FULL   = show name tags for both visible/invisible players\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    - INVIS  = show name tags for invisible players only\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    - LOCAL  = show name tags for visible players only\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '    - SIMPLE = show dots for invisible players only\n');
				g_PlayerFuncs.ClientPrint(plr, HUD_PRINTCONSOLE, '\n-----------------------------------------------------------------------------\n\n');
				
				g_PlayerFuncs.SayText(plr, "Say \".ping\" to quickly check for players.\n");
				g_PlayerFuncs.SayText(plr, "Say \".lost\" to toggle player tracking.\n");
				g_PlayerFuncs.SayText(plr, "Check your console for more info and commands.\n");
				
				return true;
			}
			
			if ( args.ArgC() >= 3 && args[1] == "hide" ) {
				state.hidden = atoi(args[2]) != 0;
				
				if (state.hidden) {
					g_PlayerFuncs.SayText(plr, "You are now hidden. No one can track you.\n");
				} else {
					g_PlayerFuncs.SayText(plr, "You are now visible. Anyone can track you.\n");
				}
				
				return true;
			}
			
			if ( args.ArgC() >= 3 && args[1] == "mode" ) {				
				string mode = args[2].ToLowercase();
				
				if (mode == "full") {
					g_PlayerFuncs.SayText(plr, "Tracking mode set to FULL. Name tags shown for all players.\n");
					state.mode = MODE_FULL;
				} else if (mode == "invis") {
					g_PlayerFuncs.SayText(plr, "Tracking mode set to INVIS. Name tags for invisible players only.\n");
					state.mode = MODE_INVIS;
				} else if (mode == "local") {
					g_PlayerFuncs.SayText(plr, "Tracking mode set to LOCAL. Name tags shown for visible players only.\n");
					state.mode = MODE_LOCAL;
				} else if (mode == "simple") {
					g_PlayerFuncs.SayText(plr, "Tracking mode set to SIMPLE. Dots shown for invisible players.\n");
					state.mode = MODE_SIMPLE;
				} else {
					g_PlayerFuncs.SayText(plr, "Unknown mode. Must be FULL, INVIS, SIMPLE, or LOCAL\n");
				}
				
				return true;
			}
			
			if ( args.ArgC() >= 2 )
			{
				@targetPlr = getPlayer(plr, args[1]);
				if (targetPlr is null)
					return true;
				if (targetPlr.entindex() == plr.entindex())
				{
					g_PlayerFuncs.SayText(plr, "Can't track yourself!\n");
					return true;
				}
			}
			
			if (state.enabled and targetPlr is null)
			{
				g_PlayerFuncs.SayText(plr, "Player tracking disabled\n");
				state.targetPlrs.deleteAll();
				state.enabled = false;
				return true;
			}
			
			if (targetPlr !is null) {
				PlayerState@ targetState = getPlayerState(targetPlr);
				
				if (targetState.hidden) {
					g_PlayerFuncs.SayText(plr, "" + targetPlr.pev.netname + " is hiding and can't be tracked.\n");
					return true;
				}
			
				state.filteredTracking = true;
				
				string targetId = getPlayerUniqueId(targetPlr);
				if (state.targetPlrs.exists(targetId)) {
					state.targetPlrs.delete(targetId);
					g_PlayerFuncs.SayText(plr, "Tracking disabled for player " + targetPlr.pev.netname + "\n");
				} else {
					state.targetPlrs[targetId] = true;
					string msg = "Tracking player " + targetPlr.pev.netname;
					if (targetPlr.Classify() != plr.Classify()) {
						msg += " (not shown currently due to being on a different team)";
					} else if (targetPlr.IsAlive() and targetPlr.GetObserver().IsObserver()) {
						msg += " (not shown currently due to being an observer)";
					}
					g_PlayerFuncs.SayText(plr, msg + "\n");
				}
			}
			else {
				state.filteredTracking = false;
				g_PlayerFuncs.SayText(plr, "Player tracking enabled\n");
			}
			
			if (!state.enabled) {
				state.enabled = true;
				g_Scheduler.SetTimeout("helpLostPlayer", 0.0f, EHandle(plr), array<LostTarget>());
			}
			
			return true;
		}
	}
	
	return false;
}

HookReturnCode ClientSay( SayParameters@ pParams )
{	
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	
	if (doCommand(plr, args))
	{
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	
	return HOOK_CONTINUE;
}

CClientCommand _lost("lost", "Find other players", @consoleCmd );
CClientCommand _lost2("ping", "Find other players", @consoleCmd );

void consoleCmd( const CCommand@ args )
{
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, args);
}

void print(string text) { g_Game.AlertMessage( at_console, text); }
void println(string text) { print(text + "\n"); }

void te_explosion(Vector pos, string sprite="sprites/zerogxplode.spr", int scale=10, int frameRate=15, int flags=0, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_EXPLOSION);m.WriteCoord(pos.x);m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(scale);m.WriteByte(frameRate);m.WriteByte(flags);m.End(); }
void te_sprite(Vector pos, string sprite="sprites/zerogxplode.spr", uint8 scale=10, uint8 alpha=200, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_SPRITE);m.WriteCoord(pos.x); m.WriteCoord(pos.y);m.WriteCoord(pos.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(scale); m.WriteByte(alpha);m.End();}
void te_beampoints(Vector start, Vector end, string sprite="sprites/laserbeam.spr", uint8 frameStart=0, uint8 frameRate=100, uint8 life=1, uint8 width=2, uint8 noise=0, Color c=GREEN, uint8 scroll=32, NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null) { NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);m.WriteByte(TE_BEAMPOINTS);m.WriteCoord(start.x);m.WriteCoord(start.y);m.WriteCoord(start.z);m.WriteCoord(end.x);m.WriteCoord(end.y);m.WriteCoord(end.z);m.WriteShort(g_EngineFuncs.ModelIndex(sprite));m.WriteByte(frameStart);m.WriteByte(frameRate);m.WriteByte(life);m.WriteByte(width);m.WriteByte(noise);m.WriteByte(c.r);m.WriteByte(c.g);m.WriteByte(c.b);m.WriteByte(c.a);m.WriteByte(scroll);m.End(); }
void te_beamtorus(Vector pos, float radius, 
	int spriteIdx, uint8 startFrame=0, 
	uint8 frameRate=16, uint8 life=8, uint8 width=8, uint8 noise=0, 
	Color c=PURPLE, uint8 scrollSpeed=0, 
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_BEAMTORUS);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z + radius);
	m.WriteShort(spriteIdx);
	m.WriteByte(startFrame);
	m.WriteByte(frameRate);
	m.WriteByte(life);
	m.WriteByte(width);
	m.WriteByte(noise);
	m.WriteByte(c.r);
	m.WriteByte(c.g);
	m.WriteByte(c.b);
	m.WriteByte(c.a);
	m.WriteByte(scrollSpeed);
	m.End();
}
void te_glowsprite(Vector pos, int dotSpriteIdx, 
	uint8 life=1, uint8 scale=10, uint8 alpha=255, 
	NetworkMessageDest msgType=MSG_BROADCAST, edict_t@ dest=null)
{
	NetworkMessage m(msgType, NetworkMessages::SVC_TEMPENTITY, dest);
	m.WriteByte(TE_GLOWSPRITE);
	m.WriteCoord(pos.x);
	m.WriteCoord(pos.y);
	m.WriteCoord(pos.z);
	m.WriteShort(dotSpriteIdx);
	m.WriteByte(life);
	m.WriteByte(scale);
	m.WriteByte(alpha);
	m.End();
}

class Color
{ 
	uint8 r, g, b, a;
	Color() { r = g = b = a = 0; }
	Color(uint8 r, uint8 g, uint8 b) { this.r = r; this.g = g; this.b = b; this.a = 255; }
	Color(uint8 r, uint8 g, uint8 b, uint8 a) { this.r = r; this.g = g; this.b = b; this.a = a; }
	Color(float r, float g, float b, float a) { this.r = uint8(r); this.g = uint8(g); this.b = uint8(b); this.a = uint8(a); }
	Color (Vector v) { this.r = uint8(v.x); this.g = uint8(v.y); this.b = uint8(v.z); this.a = 255; }
	string ToString() { return "" + r + " " + g + " " + b + " " + a; }
	Vector getRGB() { return Vector(r, g, b); }
}

Color RED    = Color(255,0,0);
Color GREEN  = Color(0,255,0);
Color BLUE   = Color(0,0,255);
Color YELLOW = Color(255,255,0);
Color ORANGE = Color(255,127,0);
Color PURPLE = Color(127,0,255);
Color PINK   = Color(255,0,127);
Color TEAL   = Color(0,255,255);
Color WHITE  = Color(255,255,255);
Color BLACK  = Color(0,0,0);
Color GRAY  = Color(127,127,127);